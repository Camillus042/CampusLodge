// ===== CampusLodge: connection to Supabase =====
// This file is loaded on every page that talks to the database.
// The anon key is meant to be public. NEVER put the service_role key here.
var SUPABASE_URL = "https://eetczjcmrekqbbmdlgzz.supabase.co";
var SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVldGN6amNtcmVrcWJibWRsZ3p6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0OTU0OTEsImV4cCI6MjEwODA3MTQ5MX0.lOJK2F2hBnMjiBz5ye_4DezU8tjShznmrylbVhULB4U";

// The address of the live site (with the slash at the end)
var SITE_URL = "https://camillus042.github.io/CampusLodge/";

// "db" is what every page uses to talk to Supabase
var db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// After login: send each person to the right home page
async function goHome() {
  var userResult = await db.auth.getUser();
  var user = userResult.data.user;
  if (!user) {
    window.location.href = "login.html";
    return;
  }

  var profileResult = await db
    .from("profiles")
    .select("role, status")
    .eq("id", user.id)
    .single();
  var profile = profileResult.data;

  if (!profile) {
    window.location.href = "error.html#oops";
  } else if (profile.status === "banned") {
    window.location.href = "appeal.html";
  } else if (profile.role === "admin") {
    window.location.href = "admin.html";
  } else if (profile.role === "student") {
    window.location.href = "dashboard.html";
  } else {
    window.location.href = "lister.html";
  }
}

// ----- Eye button on every password box -----
var EYE_OPEN = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg>';
var EYE_SHUT = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/><line x1="3" y1="3" x2="21" y2="21"/></svg>';

document.querySelectorAll('input[type="password"]').forEach(function (box) {
  // Put the box inside a wrapper so the eye can sit on top of it
  var wrap = document.createElement("div");
  wrap.className = "pw-wrap";
  box.parentNode.insertBefore(wrap, box);
  wrap.appendChild(box);

  var eye = document.createElement("button");
  eye.type = "button";
  eye.className = "pw-eye";
  eye.setAttribute("aria-label", "Show password");
  eye.innerHTML = EYE_OPEN;
  wrap.appendChild(eye);

  // Tap the eye to show or hide the password
  eye.addEventListener("click", function () {
    var isHidden = box.type === "password";
    box.type = isHidden ? "text" : "password";
    eye.innerHTML = isHidden ? EYE_SHUT : EYE_OPEN;
    eye.setAttribute("aria-label", isHidden ? "Hide password" : "Show password");
  });
});

// ===== Protect a page =====
// Use at the bottom of a page, for example protectPage(["student"])
async function protectPage(allowedRoles) {
  // Hide the page until we know the person is allowed in
  document.body.style.visibility = "hidden";

  var userResult = await db.auth.getUser();
  var user = userResult.data.user;
  if (!user) {
    window.location.href = "login.html";
    return;
  }

  var profileResult = await db
    .from("profiles")
    .select("role, status, full_name, hostel_name")
    .eq("id", user.id)
    .single();
  var profile = profileResult.data;

  if (!profile) {
    window.location.href = "error.html#oops";
    return;
  }
  if (profile.status === "banned") {
    window.location.href = "appeal.html";
    return;
  }
  if (allowedRoles && allowedRoles.indexOf(profile.role) === -1) {
    goHome();
    return;
  }

  // Names: first name for greetings, hostel name for hostels
  var firstName = (profile.full_name || "there").split(" ")[0];
  var shownName = profile.hostel_name || firstName;

  document.querySelectorAll('[data-user="first"]').forEach(function (spot) {
    spot.textContent = firstName;
  });

  document.querySelectorAll(".nav-user").forEach(function (link) {
    link.querySelector(".avatar").textContent = shownName.charAt(0).toUpperCase();
    link.lastChild.textContent = shownName;
  });

   // The "Do you want to log out?" pop-up
  var logoutBox = document.createElement("div");
  logoutBox.className = "logout-overlay";
  logoutBox.innerHTML =
    '<div class="logout-box">' +
    '<h2>Log out?</h2>' +
    '<p class="muted">You will need to log in again to use your account.</p>' +
    '<div class="logout-buttons">' +
    '<button type="button" class="btn btn-white" id="logout-cancel">Cancel</button>' +
    '<button type="button" class="btn btn-dark" id="logout-yes">Log out</button>' +
    '</div></div>';
  document.body.appendChild(logoutBox);

  // Every Log out link opens the pop-up
  document.querySelectorAll("a").forEach(function (link) {
    if (link.textContent.trim() !== "Log out") {
      return;
    }
    link.addEventListener("click", function (event) {
      event.preventDefault();
      logoutBox.classList.add("open");
    });
  });

  document.getElementById("logout-cancel").addEventListener("click", function () {
    logoutBox.classList.remove("open");
  });

  // Clicking the dark area outside the box also closes it
  logoutBox.addEventListener("click", function (event) {
    if (event.target === logoutBox) {
      logoutBox.classList.remove("open");
    }
  });

  document.getElementById("logout-yes").addEventListener("click", async function () {
    await db.auth.signOut();
    window.location.href = "index.html";
  });

  document.body.style.visibility = "visible";
}