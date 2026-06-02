const mongoose = require('mongoose');

// User Schema
const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, index: true },
  password: { type: String, required: true },
  role: { type: String, enum: ['student', 'parent'], default: 'student' },
  linkedParentId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  targetGoal: { type: String, default: '' },
  buddies: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }], // Capped at 5 max
  groupId: { type: mongoose.Schema.Types.ObjectId, ref: 'Group', default: null },
  globalScore: { type: Number, default: 0, index: true }, // Cached calculated score for sorting
  pairingCode: { type: String, default: null }, // Temp pairing code generated for linking
  pairingCodeExpires: { type: Date, default: null },
  dailyStudySeconds: { type: Number, default: 0 },
  weeklyStudySeconds: { type: Number, default: 0, index: true },
  totalStudySeconds: { type: Number, default: 0, index: true },
  
  // Real-time status for the buddy loop
  currentStatus: {
    activity: { type: String, default: 'Idle' },
    isStudying: { type: Boolean, default: false },
    lastUpdated: { type: Date, default: Date.now }
  }
});

// DailyActivity Summary Schema
const dailyActivitySchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  date: { type: String, required: true, index: true }, // YYYY-MM-DD format for fast indexing
  totalStudySeconds: { type: Number, default: 0 },
  totalDistractedSeconds: { type: Number, default: 0 },
  streakMaintained: { type: Boolean, default: false }
});

// Compound unique index so there is exactly one summary per user per day
dailyActivitySchema.index({ userId: 1, date: 1 }, { unique: true });

// Groups Schema
const groupSchema = new mongoose.Schema({
  groupName: { type: String, required: true, index: true },
  category: { type: String, required: true },
  memberCount: { type: Number, default: 0 }, // Hard cap 50 checked on API join
  creatorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true }
});

// Compile models
const User = mongoose.model('User', userSchema);
const DailyActivity = mongoose.model('DailyActivity', dailyActivitySchema);
const Group = mongoose.model('Group', groupSchema);

module.exports = { User, DailyActivity, Group };
