const dns = require("dns");
dns.setServers(["8.8.8.8", "8.8.4.4"]);

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const morgan = require("morgan");
const mongoose = require("mongoose");
const routes = require("./routes");

const app = express();
const HOST = process.env.HOST || "127.0.0.1";
const PORT = process.env.PORT || 5000;
const MONGODB_URI =
  process.env.MONGODB_URI || "mongodb://localhost:27017/minimalist-launcher";
const CORS_ORIGIN = process.env.CORS_ORIGIN || "http://localhost:8080";
const TRUST_PROXY = process.env.TRUST_PROXY === "true";
const API_RATE_WINDOW = process.env.API_RATE_WINDOW || "15m";
const API_RATE_LIMIT = Number(process.env.API_RATE_LIMIT || 100);

function parseDuration(value) {
  const numeric = Number(value);
  if (!Number.isNaN(numeric)) {
    return numeric;
  }
  const match = `${value}`.match(/^(\d+)(ms|s|m|h)$/);
  if (!match) return 15 * 60 * 1000;
  const amount = Number(match[1]);
  switch (match[2]) {
    case "ms":
      return amount;
    case "s":
      return amount * 1000;
    case "m":
      return amount * 60000;
    case "h":
      return amount * 3600000;
    default:
      return 15 * 60 * 1000;
  }
}

// Middleware
if (TRUST_PROXY) {
  app.set("trust proxy", 1);
}
app.use(helmet());
app.use(morgan(process.env.NODE_ENV === "production" ? "combined" : "dev"));
app.use(
  cors({
    origin: CORS_ORIGIN,
    credentials: true,
  }),
);
app.use(express.json({ limit: "10mb" }));
app.use(
  rateLimit({
    windowMs: parseDuration(API_RATE_WINDOW),
    max: API_RATE_LIMIT,
    standardHeaders: true,
    legacyHeaders: false,
  }),
);

// Routes
app.use("/api", routes);

// Base route for health check
app.get("/", (req, res) => {
  res.json({
    status: "online",
    message: "Minimalist Launcher API is running.",
    environment: process.env.NODE_ENV || "development",
    time: new Date(),
  });
});

app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    environment: process.env.NODE_ENV || "development",
    database:
      mongoose.connection.readyState === 1 ? "connected" : "disconnected",
    time: new Date(),
  });
});

// Start database and server
console.log(`Connecting to database at ${MONGODB_URI}...`);
mongoose
  .connect(MONGODB_URI)
  .then(() => {
    console.log("MongoDB connection established successfully.");

    // Weekly fields reset check (every minute)
    const { User } = require("./models");
    let lastResetWeek = null;
    function getUTCWeekString(d) {
      const date = new Date(
        Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()),
      );
      date.setUTCDate(date.getUTCDate() + 4 - (date.getUTCDay() || 7));
      const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
      const weekNo = Math.ceil(((date - yearStart) / 86400000 + 1) / 7);
      return `${date.getUTCFullYear()}-W${weekNo}`;
    }
    async function checkWeeklyReset() {
      try {
        const now = new Date();

        // Defensive check to ensure now is a valid Date object
        if (!(now instanceof Date) || isNaN(now.getTime())) {
          console.error(
            "Error: 'now' is not a valid Date object",
            typeof now,
            now,
          );
          return;
        }

        const day = now.getUTCDay(); // 0 is Sunday, 1 is Monday
        const hour = now.getUTCHours(); // Fixed: getUTCHour -> getUTCHours
        const weekStr = getUTCWeekString(now);

        if (day === 1 && hour === 0) {
          if (lastResetWeek !== weekStr) {
            console.log(
              "Starting weekly fields reset cron task at UTC:",
              now.toISOString(),
            );
            const result = await User.updateMany(
              { role: "student" },
              { $set: { weeklyStudySeconds: 0 } },
            );
            console.log(
              "Weekly reset completed! Updated users count:",
              result.modifiedCount,
            );
            lastResetWeek = weekStr;
          }
        }
      } catch (error) {
        console.error("Error during weekly fields reset check:", error);
      }
    }
    // Run the check every 60 seconds
    setInterval(checkWeeklyReset, 60000);

    app.listen(PORT, HOST, () => {
      console.log(`Server is running on ${HOST}:${PORT}`);
    });
  })
  .catch((err) => {
    console.error(
      "Database connection failed. Server will not start. Details:",
      err,
    );
    console.log(
      "If you do not have MongoDB running, please run a local mongodb instance or configure MONGODB_URI in your .env file.",
    );

    // Fallback mode for testing in environment without running MongoDB:
    // To allow compiling and mock validation, we could start the express server anyway, but without db operations.
    // Let's start the server anyway so the frontend can query it and we can verify endpoints with mock responses if db is off,
    // or just let it crash. Actually starting the server on a fallback mock database/in-memory setup is extremely nice for verification!
    // But let's keep it standard and prompt the user to start MongoDB if it fails.
    // To be developer-friendly, let's start the server anyway with a warning so they can see logs.
    app.listen(PORT, HOST, () => {
      console.warn(
        `[WARNING] Server started on ${HOST}:${PORT} WITHOUT database connectivity.`,
      );
    });
  });
