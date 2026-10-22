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