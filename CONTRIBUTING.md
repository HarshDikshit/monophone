# Contributing to Our Minimalist Productivity App 🚀

First off, thank you for taking the time to contribute! This project is completely open-source, and community contributions are what make it amazing. Whether you are fixing a minor bug, optimizing performance, suggesting an architectural update, or polishing the codebase, your help is incredibly welcome.

---

# 🛠️ Local Development Setup

This project consists of an **Express.js server (Backend)** and a **Flutter mobile app (Frontend)**.

Follow these steps to get your local environment running smoothly.

## 1. Prerequisites

Make sure you have the following installed on your machine:

* Flutter SDK (Latest Stable Version)
* Node.js (LTS Version) & npm
* Android Studio (Android SDK, Platform Tools & Emulator)

---

# 2. Backend Setup (Express.js)

### Navigate to the backend directory

```bash
cd backend
```

### Copy the environment file

```bash
cp .env.example .env
```

Open the newly created `.env` file and configure:

* MongoDB URI
* Server Port
* JWT/Auth Secret
* Other required environment variables

### Install dependencies

```bash
npm install
```

### Start the development server

```bash
npm start
```

---

# 3. Frontend Setup (Flutter)

### Navigate to the frontend directory

```bash
cd ../frontend
```

### Copy the environment file

```bash
cp .env.example .env
```

Open `.env` and configure the API Base URL to point to your running backend.

### Install Flutter dependencies

```bash
flutter pub get
```

---

# 📱 Running the Application

> **Important**
>
> Make sure the Express backend is running before starting the Flutter application.

## Option A — Physical Android Device (ADB)

### 1. Enable Developer Options

* Open **Settings**
* Go to **About Phone**
* Tap **Build Number** **7 times**

### 2. Enable USB Debugging

Go to:

```
Settings → Developer Options → USB Debugging
```

### 3. Connect your phone

Use a USB data cable.

### 4. Verify the device

```bash
flutter devices
```

### 5. Run the application

```bash
flutter run
```

---

## Option B — Android Studio Emulator

### 1. Open Android Studio

### 2. Open Device Manager

Create a virtual device if needed.

### 3. Start the Emulator

Click the ▶ Play button.

### 4. Verify the emulator

```bash
flutter devices
```

### 5. Run the application

```bash
flutter run
```

---

# 💡 Local Network Configuration

When running on mobile devices, `localhost` cannot reach your computer.

## Android Emulator

Use:

```
http://10.0.2.2:5000
```

instead of

```
http://localhost:5000
```

The Android Emulator uses `10.0.2.2` as an alias for your host machine.

---

## Physical Android Device

Use your computer's local Wi-Fi IP address.

Example:

```
http://192.168.1.100:5000
```

Ensure:

* Phone and computer are connected to the same Wi-Fi network.
* Firewall settings allow incoming connections if necessary.

---

# 🤝 How to Submit Code Changes

## 1. Find an Issue

Browse the project's GitHub Issues page.

Look for labels such as:

* `good first issue`
* `help wanted`

---

## 2. Fork the Repository & Create a Branch

```bash
git checkout -b feature/minimalist-layout-fix
```

---

## 3. Commit & Push

After testing your changes:

```bash
git add .
git commit -m "Describe your changes"
git push origin feature/minimalist-layout-fix
```

---

## 4. Open a Pull Request

Submit a Pull Request against the `main` branch.

Please include:

* What problem you solved
* What changes you made
* Screenshots (if UI changes)
* Any additional notes for reviewers

---

# ✅ Contribution Checklist

Before opening a Pull Request, make sure that:

* [ ] Code builds successfully.
* [ ] Flutter analyzer shows no errors.
* [ ] Backend starts without issues.
* [ ] New features are tested.
* [ ] Existing functionality is not broken.
* [ ] Documentation has been updated if necessary.

---

# ⚙️ Quick Checklist Before Publishing

Replace the placeholder below with your actual repository path:

```
YOUR_USERNAME/YOUR_REPO
```

For example:

```
john-doe/minimalist-productivity-app
```

This ensures GitHub issue links point to the correct repository.

---

## ❤️ Thank You

Thank you for contributing to this project and helping build a cleaner, distraction-free productivity experience for everyone.

Happy coding! 🚀
