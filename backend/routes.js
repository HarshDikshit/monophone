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

    // Create token
    const token = jwt.sign(
      { id: newUser._id, role: newUser.role },
      JWT_SECRET,
      { expiresIn: "7d" },
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

    const token = jwt.sign({ id: user._id, role: user.role }, JWT_SECRET, {
      expiresIn: "7d",
    });

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
    const { date, totalStudySeconds, totalDistractedSeconds } = req.body;
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

    // Upsert the daily summary document
    const summary = await DailyActivity.findOneAndUpdate(
      { userId: req.user.id, date },
      {
        totalStudySeconds,
        totalDistractedSeconds,
        streakMaintained,
      },
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
        .json({ message: "Group is full (hard cap of 50 members reached)" });
    }

    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ message: "User not found" });

    // Leave old group if currently in one
    if (user.groupId) {
      await Group.findByIdAndUpdate(user.groupId, {
        $inc: { memberCount: -1 },
      });
    }

    // Join new group
    user.groupId = targetGroup._id;
    await user.save();

    // Increment member count in new group
    targetGroup.memberCount += 1;
    await targetGroup.save();

    res.json({
      message: `Successfully joined group ${targetGroup.groupName}`,
      group: targetGroup,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

let cachedOverallRankings = null;
let lastFetchedOverall = 0;
let cachedWeeklyRankings = null;
let lastFetchedWeekly = 0;

const LEADERBOARD_CACHE_DURATION = 15 * 60 * 1000; // 15 Minutes Cache

router.get("/rankings", authenticateToken, async (req, res) => {
  try {
    const category = req.query.category || "overall";
    const skip = parseInt(req.query.skip) || 0;
    const limit = parseInt(req.query.limit) || 10;
    const now = Date.now();

    let rankingsList = [];

    if (category === "weekly") {
      if (
        !cachedWeeklyRankings ||
        now - lastFetchedWeekly > LEADERBOARD_CACHE_DURATION
      ) {
        // Query database
        cachedWeeklyRankings = await User.find({ role: "student" })
          .select("name targetGoal weeklyStudySeconds dailyStudySeconds")
          .sort({ weeklyStudySeconds: -1 });
        lastFetchedWeekly = now;
      }
      rankingsList = cachedWeeklyRankings;
    } else {
      if (
        !cachedOverallRankings ||
        now - lastFetchedOverall > LEADERBOARD_CACHE_DURATION
      ) {
        // Query database
        cachedOverallRankings = await User.find({ role: "student" })
          .select("name targetGoal totalStudySeconds dailyStudySeconds")
          .sort({ totalStudySeconds: -1 });
        lastFetchedOverall = now;
      }
      rankingsList = cachedOverallRankings;
    }

    // Find current user's index (rank is index + 1)
    const myIndex = rankingsList.findIndex(
      (u) => u._id.toString() === req.user.id,
    );
    const myRank = myIndex !== -1 ? myIndex + 1 : 0;
    const myUser = myIndex !== -1 ? rankingsList[myIndex] : null;

    // Slice for pagination
    const paginatedList = rankingsList.slice(skip, skip + limit);

    res.json({
      rankings: paginatedList,
      totalCount: rankingsList.length,
      myRank,
      myStats:
        myUser ?
          {
            name: myUser.name,
            targetGoal: myUser.targetGoal,
            score:
              category === "weekly" ?
                myUser.weeklyStudySeconds
              : myUser.totalStudySeconds,
          }
        : null,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// OFFLINE BEHAVIOR AI MOTIVATOR
// ----------------------------------------------------

router.post("/ai/behavior-guide", authenticateToken, async (req, res) => {
  try {
    const { studySeconds, distractedSeconds, examGoal } = req.body;
    if (studySeconds === undefined || distractedSeconds === undefined) {
      return res
        .status(400)
        .json({ message: "studySeconds and distractedSeconds are required" });
    }

    const targetGoal = examGoal || "your goals";
    const studyMins = Math.round(studySeconds / 60);
    const distractedMins = Math.round(distractedSeconds / 60);

    // Tough-love generator offline rules (2 sentences maximum)
    let message = "";

    if (studyMins === 0 && distractedMins === 0) {
      message = `Zero study minutes today for ${targetGoal}. Your competition is currently masterfully studying while you lie dormant. Wake up!`;
    } else if (studyMins === 0 && distractedMins > 0) {
      message = `You spent ${distractedMins}m on distractions and 0m preparing for ${targetGoal}. That is an embarrassing ratio. Close the applications and focus!`;
    } else if (studyMins > 0 && distractedMins > studyMins * 2) {
      message = `Only ${studyMins}m of study against a whopping ${distractedMins}m of scrolling. You are actively choosing failure for ${targetGoal}. Get your acts together immediately!`;
    } else if (studyMins > 0 && distractedMins > 0) {
      const ratio = ((studyMins / (studyMins + distractedMins)) * 100).toFixed(
        0,
      );
      message = `Your focus ratio for ${targetGoal} is ${ratio}% (${studyMins}m focus vs ${distractedMins}m distraction). Don't let cheap dopamine hijack your hard work. Push harder tomorrow.`;
    } else if (studyMins > 0 && distractedMins === 0) {
      message = `Excellent: ${studyMins}m of pure study for ${targetGoal} with zero distractions. You are standardizing success. Keep this exact momentum going.`;
    } else {
      message = `Every single second spent scrolling is a step away from ${targetGoal}. Guard your time like your life depends on it, because your future does.`;
    }

    res.json({ message });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────
// VERSION CHECK ENDPOINT (PUBLIC - NO AUTH REQUIRED)
// ─────────────────────────────────────────────────────────────────────────
// This endpoint is used by the mobile app to check for available updates
router.get("/version", (req, res) => {
  try {
    const versionInfo = {
      latestVersion: LATEST_VERSION,
      isCriticalUpdate: false,
      downloadUrl: `${OTA_DOWNLOAD_URL}/v${LATEST_VERSION}/app-arm64-v8a-release.apk`,
      releaseNotes: RELEASE_NOTES,
      minSupportedVersion: MIN_SUPPORTED_VERSION,
    };
    res.json(versionInfo);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// ----------------------------------------------------
// BUG REPORTING ENDPOINT
// ----------------------------------------------------
router.post("/support/bug-report", async (req, res) => {
  try {
    const { title, description, reporterEmail, appVersion, platform } = req.body;

    if (!title || !description) {
      return res.status(400).json({
        message: "Bug report title and description are required.",
      });
    }

    const report = {
      title,
      description,
      reporterEmail: reporterEmail || "unknown",
      appVersion: appVersion || "unknown",
      platform: platform || "unknown",
      userAgent: req.headers["user-agent"],
      ip: req.ip,
    };

    recordBugReport(report);

    res.json({
      message:
        "Your bug report has been recorded successfully. Thank you for helping us improve the app.",
      intendedRecipient: BUG_REPORT_EMAIL,
    });
  } catch (error) {
    console.error("Bug report failed:", error);
    res.status(500).json({
      message:
        "Unable to send bug report right now. Please try again later.",
    });
  }
});

module.exports = router;
