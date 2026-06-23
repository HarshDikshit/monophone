const express = require("express");
const fs = require("fs");
const router = express.Router();
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { User, DailyActivity, Group } = require("./models");

// JWT Secret
const JWT_SECRET = process.env.JWT_SECRET || "supersecretjwtkey12345";
const OTA_DOWNLOAD_URL =
  process.env.OTA_DOWNLOAD_URL ||
  "https://github.com/yourusername/monophone/releases/download";
const LATEST_VERSION = process.env.APP_LATEST_VERSION || "1.0.1";
const MIN_SUPPORTED_VERSION = process.env.APP_MIN_SUPPORTED_VERSION || "0.9.0";
const RELEASE_NOTES =
  process.env.APP_RELEASE_NOTES || "Bug fixes and performance improvements.";

const Redis = require("ioredis");

// Initialize Redis client (optional - falls back to in-memory cache if unavailable)
const REDIS_URL = process.env.REDIS_URL || "";
let redisClient = null;
let isRedisConnected = false;

if (REDIS_URL) {
  try {
    redisClient = new Redis(REDIS_URL, {
      maxRetriesPerRequest: null,
      retryStrategy(times) {
        // Do not auto-reconnect; we'll rely on the in-memory fallback
        return null;
      },
      connectTimeout: 2000,
      lazyConnect: true,
    });

    redisClient.on("connect", () => {
      console.log("Redis connected successfully.");
      isRedisConnected = true;
    });

    redisClient.on("error", (err) => {
      if (!isRedisConnected) {
        // Only log the first error to avoid spamming the console
        console.warn(
          "Redis is not available. Cache operations will use in-memory fallback.",
        );
      }
      isRedisConnected = false;
    });

    redisClient.on("end", () => {
      isRedisConnected = false;
    });

    redisClient.connect().catch(() => {
      if (isRedisConnected !== false) {
        console.warn(
          "Redis connection failed. Using in-memory cache fallback.",
        );
      }
      isRedisConnected = false;
    });
  } catch (error) {
    console.warn(
      "Failed to initialize Redis client. Using in-memory cache fallback.",
    );
    isRedisConnected = false;
  }
} else {
  console.log(
    "REDIS_URL not configured. Using in-memory cache fallback.",
  );
}

// In-memory fallback cache
const analyticsCache = new Map();
const CACHE_TTL_MS = 60 * 1000;

async function getCached(key) {
  if (isRedisConnected && redisClient) {
    try {
      const data = await redisClient.get(key);
      if (data) {
        return JSON.parse(data);
      }
      return null;
    } catch (err) {
      console.error("Redis getCached error, falling back to memory:", err.message);
    }
  }

  const entry = analyticsCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > CACHE_TTL_MS) {
    analyticsCache.delete(key);
    return null;
  }
  return entry.data;
}

async function setCached(key, data) {
  const ttlSeconds = 60;
  if (isRedisConnected && redisClient) {
    try {
      await redisClient.set(key, JSON.stringify(data), "EX", ttlSeconds);
      return;
    } catch (err) {
      console.error("Redis setCached error, falling back to memory:", err.message);
    }
  }

  analyticsCache.set(key, { timestamp: Date.now(), data });
  if (analyticsCache.size > 1000) {
    const firstKey = analyticsCache.keys().next().value;
    analyticsCache.delete(firstKey);
  }
}

async function invalidateUserAnalytics(userId) {
  if (isRedisConnected && redisClient) {
    try {
      const pattern = `analytics:${userId}:*`;
      let cursor = "0";
      do {
        const res = await redisClient.scan(cursor, "MATCH", pattern, "COUNT", 100);
        cursor = res[0];
        const keys = res[1];
        if (keys.length > 0) {
          await redisClient.del(...keys);
        }
      } while (cursor !== "0");
      return;
    } catch (err) {
      console.error("Redis invalidateUserAnalytics error, falling back to memory:", err.message);
    }
  }

  for (const k of analyticsCache.keys()) {
    if (k.startsWith(`analytics:${userId}`)) {
      analyticsCache.delete(k);
    }
  }
}

const BUG_REPORT_EMAIL =
  process.env.BUG_REPORT_EMAIL || process.env.SUPPORT_EMAIL ||
  "support@yourdomain.com";
const BUG_REPORT_LOG_FILE =
  process.env.BUG_REPORT_LOG_FILE || "backend/bug-reports.log";

function recordBugReport(report) {
  const reportEntry = `Bug report intended for ${BUG_REPORT_EMAIL}
Title: ${report.title}
Reporter: ${report.reporterEmail || "unknown"}
Version: ${report.appVersion || "unknown"}
Platform: ${report.platform || "unknown"}
User Agent: ${report.userAgent || "unknown"}
IP: ${report.ip || "unknown"}

Description:
${report.description}

---\n`;

  try {
    fs.appendFileSync(BUG_REPORT_LOG_FILE, reportEntry, "utf8");
  } catch (error) {
    console.error("Failed to write bug report log:", error);
  }

  console.info(reportEntry);
}

// Middleware to authenticate JWT token
function authenticateToken(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];
  if (!token) return res.status(401).json({ message: "Access token required" });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err)
      return res.status(403).json({ message: "Invalid or expired token" });
    req.user = user;
    next();
  });
}

function getRecentMondayDate() {
  const d = new Date();
  const day = d.getUTCDay();
  const diff = d.getUTCDate() - day + (day === 0 ? -6 : 1);
  const monday = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), diff));
  const year = monday.getUTCFullYear();
  const month = String(monday.getUTCMonth() + 1).padStart(2, "0");
  const date = String(monday.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${date}`;
}

// ----------------------------------------------------
// AUTH ENDPOINTS
// ----------------------------------------------------

// Register
router.post("/auth/register", async (req, res) => {
  try {
    const { name, email, password, role } = req.body;
    if (!name || !email || !password) {
      return res
        .status(400)
        .json({ message: "Name, email, and password are required" });
    }

    const existingUser = await User.findOne({ email: email.toLowerCase() });
    if (existingUser) {
      return res
        .status(400)
        .json({ message: "User with this email already exists" });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const newUser = new User({
      name,
      email: email.toLowerCase(),
      password: hashedPassword,
      role: role || "student",
      buddies: [],
      globalScore: 0,
    });

    await newUser.save();

    // Create token — NO expiry so users never need to re-login
    const token = jwt.sign(
      { id: newUser._id, role: newUser.role },
      JWT_SECRET,
    );

    res.status(201).json({
      token,
      user: {
        id: newUser._id,
        name: newUser.name,
        email: newUser.email,
        role: newUser.role,
      },
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Login
router.post("/auth/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res
        .status(400)
        .json({ message: "Email and password are required" });
    }

    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) {
      return res.status(400).json({ message: "Invalid email or password" });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(400).json({ message: "Invalid email or password" });
    }

    // Create token — NO expiry so users never need to re-login
    const token = jwt.sign({ id: user._id, role: user.role }, JWT_SECRET);

    res.json({
      token,
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        role: user.role,
      },
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// All routes below unchanged...
// ── existing code continues unchanged past this point ──

// ----------------------------------------------------
// USER PROFILE & GOAL ENDPOINTS
// ----------------------------------------------------

// Get Profile
router.get("/user/profile", authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.user.id)
      .select("-password")
      .populate("groupId", "groupName category memberCount creatorId")
      .populate("buddies", "name email currentStatus");
    if (!user) return res.status(404).json({ message: "User not found" });
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Update Goal
router.put("/user/goal", authenticateToken, async (req, res) => {
  try {
    const { targetGoal } = req.body;
    const user = await User.findByIdAndUpdate(
      req.user.id,
      { targetGoal: targetGoal || "" },
      { new: true },
    ).select("-password");
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Update Current Status (Real-time study status)
router.put("/user/status", authenticateToken, async (req, res) => {
  try {
    const { activity, isStudying } = req.body;
    const user = await User.findByIdAndUpdate(
      req.user.id,
      {
        currentStatus: {
          activity: activity || "Idle",
          isStudying: !!isStudying,
          lastUpdated: new Date(),
        },
      },
      { new: true },
    ).select("-password");
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// PARENT LINKING & REPORT ENDPOINTS
// ----------------------------------------------------

// Generate Pairing Code (Student Endpoint)
router.get("/user/parent-pairing-code", authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== "student") {
      return res
        .status(403)
        .json({ message: "Only students can generate pairing codes" });
    }

    // Generate a simple 6-character alphanumeric pairing code
    const code = Math.random().toString(36).substring(2, 8).toUpperCase();
    const expiry = new Date(Date.now() + 15 * 60 * 1000); // 15 mins expiry

    await User.findByIdAndUpdate(req.user.id, {
      pairingCode: code,
      pairingCodeExpires: expiry,
    });

    res.json({ pairingCode: code, expiresAt: expiry });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Pair Parent (Parent Endpoint)
router.post("/parent/pair", authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== "parent") {
      return res
        .status(403)
        .json({ message: "Only parents can pair with students" });
    }

    const { pairingCode } = req.body;
    if (!pairingCode) {
      return res.status(400).json({ message: "Pairing code is required" });
    }

    // Find student with valid matching code
    const student = await User.findOne({
      pairingCode: pairingCode.toUpperCase(),
      pairingCodeExpires: { $gt: new Date() },
      role: "student",
    });

    if (!student) {
      return res
        .status(400)
        .json({ message: "Invalid or expired pairing code" });
    }

    // Link parent to student
    student.linkedParentId = req.user.id;
    // Clear pairing code
    student.pairingCode = null;
    student.pairingCodeExpires = null;
    await student.save();

    res.json({
      message: `Successfully linked with student ${student.name}`,
      student: {
        id: student._id,
        name: student.name,
        email: student.email,
      },
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Get Linked Students (Parent Endpoint)
router.get("/parent/students", authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== "parent") {
      return res.status(403).json({ message: "Only parents can view linked students" });
    }
    const students = await User.find({ linkedParentId: req.user.id })
      .select("name email currentStatus targetGoal globalScore dailyStudySeconds weeklyStudySeconds totalStudySeconds");
    res.json(students);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Get Parent Reports for Student
router.get(
  "/parent/reports/:studentId",
  authenticateToken,
  async (req, res) => {
    try {
      const { studentId } = req.params;

      // Authorization check: User must be a parent, and student's linkedParentId must equal parent's id
      const student = await User.findById(studentId);
      if (!student) {
        return res.status(404).json({ message: "Student not found" });
      }

      const isAuthorized =
        req.user.role === "parent" &&
        student.linkedParentId &&
        student.linkedParentId.toString() === req.user.id;
      // Alternatively, a student can also view their own reports
      const isSelf = req.user.id === studentId;

      if (!isAuthorized && !isSelf) {
        return res
          .status(403)
          .json({ message: "Unauthorized to view this student's activity" });
      }

      // Fetch student's activities sorted by date descending (limit last 30 days)
      const activities = await DailyActivity.find({ userId: studentId })
        .sort({ date: -1 })
        .limit(30);

      res.json({
        student: {
          id: student._id,
          name: student.name,
          targetGoal: student.targetGoal,
        },
        activities,
      });
    } catch (error) {
      res.status(500).json({ message: error.message });
    }
  },
);

// ----------------------------------------------------
// DAILY ACTIVITY SYNC (OPTIMIZED FREE TIER)
// ----------------------------------------------------

// Sync Daily summary (upsert a single pre-calculated daily summary document per user)
router.post("/activity/sync", authenticateToken, async (req, res) => {
  try {
    const {
      date,
      totalStudySeconds,
      totalDistractedSeconds,
      hourly,
      taskAnalytics,
      sessions
    } = req.body;
    if (
      !date ||
      totalStudySeconds === undefined ||
      totalDistractedSeconds === undefined
    ) {
      return res.status(400).json({
        message:
          "date, totalStudySeconds, and totalDistractedSeconds are required",
      });
    }

    // A streak is maintained if study is > 30 minutes (1800 seconds)
    const streakMaintained = totalStudySeconds >= 1800;

    // Build update object
    const update = {
      totalStudySeconds,
      totalDistractedSeconds,
      streakMaintained,
    };
    if (hourly) update.hourly = hourly;
    if (taskAnalytics) update.taskAnalytics = taskAnalytics;
    if (sessions) update.sessions = sessions;

    // Upsert the daily summary document
    const summary = await DailyActivity.findOneAndUpdate(
      { userId: req.user.id, date },
      { $set: update },
      { new: true, upsert: true },
    );

    // Calculate dynamic globalScore
    // Formula: sum of study seconds in past 7 days + (number of active streak days * 3600)
    const recentActivities = await DailyActivity.find({
      userId: req.user.id,
    })
      .sort({ date: -1 })
      .limit(7);

    let recentStudySecondsSum = 0;
    let streakCount = 0;
    for (let i = 0; i < recentActivities.length; i++) {
      recentStudySecondsSum += recentActivities[i].totalStudySeconds;
      if (recentActivities[i].streakMaintained) {
        streakCount++;
      }
    }

    const calculatedScore = recentStudySecondsSum + streakCount * 3600;

    // Update user's dailyStudySeconds if this sync is for today
    const todayStr = new Date().toISOString().split("T")[0];
    if (date === todayStr) {
      await User.findByIdAndUpdate(req.user.id, {
        dailyStudySeconds: totalStudySeconds,
      });
    }

    // Update user's weeklyStudySeconds (since Monday)
    const mondayStr = getRecentMondayDate();
    const weeklyActivities = await DailyActivity.find({
      userId: req.user.id,
      date: { $gte: mondayStr },
    });
    let weeklySeconds = 0;
    for (const act of weeklyActivities) {
      weeklySeconds += act.totalStudySeconds;
    }

    // Update user's totalStudySeconds (overall across all time)
    const allActivities = await DailyActivity.find({ userId: req.user.id });
    let totalSeconds = 0;
    for (const act of allActivities) {
      totalSeconds += act.totalStudySeconds;
    }

    // Update student's profile scores and times
    await User.findByIdAndUpdate(req.user.id, {
      globalScore: calculatedScore,
      weeklyStudySeconds: weeklySeconds,
      totalStudySeconds: totalSeconds,
    });

    res.json({
      summary,
      globalScore: calculatedScore,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// BATCH SYNC (timer start, pause, stop, break_start, break_end)
// Lightweight event endpoint.  Used by the mobile app to notify the
// backend whenever the Pomodoro timer changes state.  Avoids the heavy
// /activity/sync endpoint for event-only updates.
// ----------------------------------------------------
router.post("/activity/batch-sync", authenticateToken, async (req, res) => {
  try {
    const { event, timestamp, currentDay } = req.body;
    if (!event || !timestamp) {
      return res
        .status(400)
        .json({ message: "event and timestamp are required" });
    }

    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    if (currentDay) {
      const streakMaintained = (user.dailyStudySeconds || 0) >= 1800;
      await DailyActivity.findOneAndUpdate(
        { userId: req.user.id, date: currentDay },
        {
          $set: {
            streakMaintained,
            lastEvent: event,
            lastEventAt: new Date(timestamp),
          },
        },
        { upsert: true, new: true },
      );
    }

    // Recalculate globalScore.
    const recentActivities = await DailyActivity.find({ userId: req.user.id })
      .sort({ date: -1 })
      .limit(7);
    let recentStudySecondsSum = 0;
    let streakCount = 0;
    for (const act of recentActivities) {
      recentStudySecondsSum += act.totalStudySeconds;
      if (act.streakMaintained) streakCount++;
    }
    const calculatedScore = recentStudySecondsSum + streakCount * 3600;

    await User.findByIdAndUpdate(req.user.id, {
      globalScore: calculatedScore,
    });

    // Invalidate analytics cache so the next /analytics fetch returns fresh data.
    await invalidateUserAnalytics(req.user.id);

    res.json({
      success: true,
      event,
      globalScore: calculatedScore,
      message: `Event '${event}' recorded`,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// COMPREHENSIVE ANALYTICS ENDPOINT
// Cached for 60 seconds to avoid hammering MongoDB for frequently
// viewed analytics dashboards.
// ----------------------------------------------------
router.get("/analytics", authenticateToken, async (req, res) => {
  try {
    const daysBack = parseInt(req.query.days) || 30;
    const { studentId } = req.query;
    
    // Determine the subject of analytics. Default is the current user.
    let targetUserId = req.user.id;
    
    if (studentId) {
      const student = await User.findById(studentId);
      if (!student) {
        return res.status(404).json({ message: "Student not found" });
      }
      
      // Authorization check: Parent must be linked, or student viewing themselves
      const isAuthorized = 
        req.user.id === studentId || 
        (req.user.role === "parent" && student.linkedParentId && student.linkedParentId.toString() === req.user.id);
        
      if (!isAuthorized) {
        return res.status(403).json({ message: "Unauthorized to view this student's analytics" });
      }
      
      targetUserId = studentId;
    }

    const cacheKey = `analytics:${targetUserId}:${daysBack}`;

    const cached = await getCached(cacheKey);
    if (cached) {
      return res.json({ ...cached, _fromCache: true });
    }

    const user = await User.findById(targetUserId)
      .select("-password")
      .populate("groupId", "groupName category memberCount creatorId");
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const cutoffDate = new Date();
    cutoffDate.setUTCDate(cutoffDate.getUTCDate() - daysBack);
    const cutoffDateStr = cutoffDate.toISOString().split("T")[0];

    const activities = await DailyActivity.find({
      userId: req.user.id,
      date: { $gte: cutoffDateStr },
    }).sort({ date: 1 });

    // Per-day map for quick lookup.
    const dailyMap = {};
    for (const act of activities) {
      dailyMap[act.date] = {
        date: act.date,
        studySeconds: act.totalStudySeconds || 0,
        distractedSeconds: act.totalDistractedSeconds || 0,
        streakMaintained: act.streakMaintained || false,
        lastEvent: act.lastEvent || null,
        lastEventAt: act.lastEventAt || null,
        hourly: act.hourly || new Array(24).fill(0),
        taskAnalytics: act.taskAnalytics || [],
        sessions: act.sessions || []
      };
    }

    // Fill empty days so the calendar is continuous.
    const dailyList = [];
    for (let i = daysBack - 1; i >= 0; i--) {
      const d = new Date();
      d.setUTCDate(d.getUTCDate() - i);
      const key = d.toISOString().split("T")[0];
      dailyList.push(
        dailyMap[key] || {
          date: key,
          studySeconds: 0,
          distractedSeconds: 0,
          streakMaintained: false,
          lastEvent: null,
          lastEventAt: null,
          hourly: new Array(24).fill(0),
          taskAnalytics: [],
          sessions: []
        },
      );
    }

    // Aggregate metrics.
    let totalStudySeconds = 0;
    let totalDistractedSeconds = 0;
    let streakDays = 0;
    let activeDays = 0;
    let maxDayStudy = 0;
    let mostProductiveDay = null;
    for (const day of dailyList) {
      totalStudySeconds += day.studySeconds;
      totalDistractedSeconds += day.distractedSeconds;
      if (day.streakMaintained) streakDays++;
      if (day.studySeconds > 0) activeDays++;
      if (day.studySeconds > maxDayStudy) {
        maxDayStudy = day.studySeconds;
        mostProductiveDay = day.date;
      }
    }
    const totalSeconds = totalStudySeconds + totalDistractedSeconds;
    const focusRatio = totalSeconds > 0
      ? Math.round((totalStudySeconds / totalSeconds) * 100)
      : 0;
    const averageDailySeconds = daysBack > 0
      ? Math.round(totalStudySeconds / daysBack)
      : 0;

    // Period breakdowns.
    const today = new Date().toISOString().split("T")[0];
    const todayData = dailyMap[today] || { studySeconds: 0, distractedSeconds: 0 };
    const oneWeekAgo = new Date();
    oneWeekAgo.setUTCDate(oneWeekAgo.getUTCDate() - 7);
    const weekStart = oneWeekAgo.toISOString().split("T")[0];
    let weeklyStudySeconds = 0;
    let weeklyDistractedSeconds = 0;
    for (const day of dailyList) {
      if (day.date >= weekStart) {
        weeklyStudySeconds += day.studySeconds;
        weeklyDistractedSeconds += day.distractedSeconds;
      }
    }

    // Hourly distribution - prioritize explicit hourly data if available,
    // otherwise fallback to lastEventAt logic (for legacy data)
    let hourlyDistribution = new Array(24).fill(0);
    // If we're looking at a single day (today), we can return its specific hourly data
    const todayStr = new Date().toISOString().split("T")[0];
    const targetDay = dailyMap[todayStr];
    if (targetDay && targetDay.hourly && targetDay.hourly.some(v => v > 0)) {
        hourlyDistribution = targetDay.hourly;
    } else {
        // Fallback for aggregate views or legacy data
        for (const act of activities) {
            if (act.hourly && act.hourly.some(v => v > 0)) {
                for (let i = 0; i < 24; i++) {
                    hourlyDistribution[i] += act.hourly[i] || 0;
                }
            } else if (act.lastEventAt) {
                const hr = new Date(act.lastEventAt).getUTCHours();
                hourlyDistribution[hr] += act.totalStudySeconds || 0;
            }
        }
    }

    // Build the response payload.
    const response = {
      user: {
        id: user._id,
        name: user.name,
        targetGoal: user.targetGoal,
        globalScore: user.globalScore,
        currentStreak: user.dailyStudySeconds,
        weeklyStudySeconds: user.weeklyStudySeconds,
        totalStudySeconds: user.totalStudySeconds,
      },
      summary: {
        todayStudySeconds: todayData.studySeconds || 0,
        todayDistractedSeconds: todayData.distractedSeconds || 0,
        weeklyStudySeconds,
        weeklyDistractedSeconds,
        monthlyStudySeconds: totalStudySeconds,
        monthlyDistractedSeconds: totalDistractedSeconds,
        averageDailySeconds,
        focusRatio,
        activeDays,
        streakDays,
        mostProductiveDay,
        mostProductiveDaySeconds: maxDayStudy,
      },
      daily: dailyList,
      hourly: hourlyDistribution,
      fromCache: false,
    };

    await setCached(cacheKey, response);
    res.json(response);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// BUDDIES (LOVED ONES LOOP)
// ----------------------------------------------------

// Add Buddy (Max 5 buddies)
router.post("/buddies/add", authenticateToken, async (req, res) => {
  try {
    const { buddyEmail } = req.body;
    if (!buddyEmail) {
      return res.status(400).json({ message: "Buddy email is required" });
    }

    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ message: "User not found" });

    if (user.buddies.length >= 5) {
      return res
        .status(400)
        .json({ message: "Maximum limit of 5 buddies reached" });
    }

    const buddy = await User.findOne({
      email: buddyEmail.toLowerCase(),
      role: "student",
    });
    if (!buddy) {
      return res
        .status(404)
        .json({ message: "Buddy student profile not found" });
    }

    if (buddy._id.toString() === req.user.id) {
      return res
        .status(400)
        .json({ message: "You cannot add yourself as a buddy" });
    }

    if (user.buddies.includes(buddy._id)) {
      return res
        .status(400)
        .json({ message: "This user is already your buddy" });
    }

    user.buddies.push(buddy._id);
    await user.save();

    res.json({
      message: `Successfully added ${buddy.name} as buddy`,
      buddies: user.buddies,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Get Buddies Status (Real-time Status tracking)
router.get("/buddies/status", authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.user.id).populate(
      "buddies",
      "name email currentStatus",
    );
    if (!user) return res.status(404).json({ message: "User not found" });

    res.json(user.buddies);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// PUBLIC ACCOUNTABILITY RANKINGS
// ----------------------------------------------------

// Get Rankings
router.get("/rankings", authenticateToken, async (req, res) => {
  try {
    const { category, skip, limit } = req.query;
    const skipNum = parseInt(skip) || 0;
    const limitNum = parseInt(limit) || 20;

    let sortField = "totalStudySeconds";
    if (category === "thisweek") {
      sortField = "weeklyStudySeconds";
    }

    // Return students only for the leaderboard
    const rankingData = await User.find({ role: "student" })
      .select("name email weeklyStudySeconds totalStudySeconds")
      .sort({ [sortField]: -1 })
      .skip(skipNum)
      .limit(limitNum);

    const rankings = rankingData.map((user) => ({
      username: user.name,
      totalFocusSeconds: user[sortField] || 0,
    }));

    res.json({ rankings });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// PUBLIC ACCOUNTABILITY GROUPS (CAP 50)
// ----------------------------------------------------

// List Groups
router.get("/groups", authenticateToken, async (req, res) => {
  try {
    const groups = await Group.find({});
    res.json(groups);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Search Groups with regex lookup (debounced on client side)
router.get("/groups/search", authenticateToken, async (req, res) => {
  try {
    const { query } = req.query;
    if (!query) {
      const groups = await Group.find({});
      return res.json(groups);
    }
    // Target text regex queries straight into the indexed backend group collection
    const groups = await Group.find({
      groupName: { $regex: query, $options: "i" },
    });
    res.json(groups);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Get members of a specific group
router.get("/groups/:groupId/members", authenticateToken, async (req, res) => {
  try {
    const { groupId } = req.params;
    const user = await User.findById(req.user.id);
    if (!user || !user.groupId || user.groupId.toString() !== groupId) {
      return res.status(403).json({
        message:
          "Unauthorized. You must be a member of this group to view its details.",
      });
    }

    const members = await User.find({ groupId })
      .select(
        "name email role currentStatus dailyStudySeconds weeklyStudySeconds",
      )
      .sort({ weeklyStudySeconds: -1 });

    res.json(members);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Remove Member (Admin Eviction)
router.post("/groups/remove-member", authenticateToken, async (req, res) => {
  try {
    const { targetUserId } = req.body;
    if (!targetUserId) {
      return res.status(400).json({ message: "targetUserId is required" });
    }

    const user = await User.findById(req.user.id);
    if (!user || !user.groupId) {
      return res.status(400).json({ message: "You are not in a group" });
    }

    const group = await Group.findById(user.groupId);
    if (!group) {
      return res.status(404).json({ message: "Group not found" });
    }

    // if Group.creatorId == CurrentUser.id
    if (group.creatorId.toString() !== req.user.id) {
      return res
        .status(403)
        .json({ message: "Only the group creator can remove members" });
    }

    const targetUser = await User.findById(targetUserId);
    if (
      !targetUser ||
      !targetUser.groupId ||
      targetUser.groupId.toString() !== group._id.toString()
    ) {
      return res
        .status(400)
        .json({ message: "Target user is not in your group" });
    }

    if (targetUserId === req.user.id) {
      return res.status(400).json({ message: "You cannot remove yourself" });
    }

    targetUser.groupId = null;
    await targetUser.save();

    group.memberCount = Math.max(0, group.memberCount - 1);
    await group.save();

    res.json({ message: "Successfully removed member from the group" });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Create Group
router.post("/groups/create", authenticateToken, async (req, res) => {
  try {
    const { groupName, category } = req.body;
    if (!groupName || !category) {
      return res
        .status(400)
        .json({ message: "groupName and category are required" });
    }

    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ message: "User not found" });

    const newGroup = new Group({
      groupName,
      category,
      memberCount: 1,
      creatorId: req.user.id,
    });
    await newGroup.save();

    // Leave old group if currently in one
    if (user.groupId) {
      await Group.findByIdAndUpdate(user.groupId, {
        $inc: { memberCount: -1 },
      });
    }

    user.groupId = newGroup._id;
    await user.save();

    res.status(201).json(newGroup);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Join Group (Capped at 50 max)
router.post("/groups/join", authenticateToken, async (req, res) => {
  try {
    const { groupId } = req.body;
    if (!groupId) {
      return res.status(400).json({ message: "groupId is required" });
    }

    const targetGroup = await Group.findById(groupId);
    if (!targetGroup) {
      return res.status(404).json({ message: "Group not found" });
    }

    if (targetGroup.memberCount >= 50) {
      return res
        .status(400)
        .json({ message: "Group is at maximum capacity (50 members)" });
    }

    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ message: "User not found" });

    // Leave old group if currently in one
    if (user.groupId) {
      await Group.findByIdAndUpdate(user.groupId, {
        $inc: { memberCount: -1 },
      });
    }

    user.groupId = targetGroup._id;
    await user.save();

    targetGroup.memberCount += 1;
    await targetGroup.save();

    res.json({ message: "Successfully joined the group", group: targetGroup });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Leave Group
router.post("/groups/leave", authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user || !user.groupId) {
      return res.status(400).json({ message: "You are not in a group" });
    }

    await Group.findByIdAndUpdate(user.groupId, {
      $inc: { memberCount: -1 },
    });

    user.groupId = null;
    await user.save();

    res.json({ message: "Successfully left the group" });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// OTA APP UPDATE ENDPOINT
// ----------------------------------------------------

router.get("/ota/latest", (req, res) => {
  res.json({
    latestVersion: LATEST_VERSION,
    minSupportedVersion: MIN_SUPPORTED_VERSION,
    downloadUrl: OTA_DOWNLOAD_URL,
    releaseNotes: RELEASE_NOTES,
  });
});

// ----------------------------------------------------
// BUG REPORT ENDPOINT
// ----------------------------------------------------

router.post("/bug-report", (req, res) => {
  try {
    const { title, description, reporterEmail, appVersion, platform, userAgent } = req.body;

    if (!title || !description) {
      return res.status(400).json({ message: "Title and description are required" });
    }

    const report = {
      title,
      description,
      reporterEmail,
      appVersion,
      platform,
      userAgent,
      ip: req.ip || req.connection?.remoteAddress || "unknown",
    };

    recordBugReport(report);

    res.json({
      success: true,
      message:
        "Bug report recorded. Please email details to " + BUG_REPORT_EMAIL,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// APP VERSION, FEATURE FLAGS, & MAINTENANCE WINDOW
// OTA-friendly: minimal, cached response for launcher to poll.
// ----------------------------------------------------
router.get("/app-update", (req, res) => {
  res.json({
    latestVersion: LATEST_VERSION,
    minSupportedVersion: MIN_SUPPORTED_VERSION,
    forceUpdate: false,
    downloadUrl: OTA_DOWNLOAD_URL,
    releaseNotes: RELEASE_NOTES,
    maintenanceWindow: null,
  });
});

module.exports = router;