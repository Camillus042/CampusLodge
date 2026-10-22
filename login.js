// ===== Login: check the boxes, then log in with Supabase =====
var loginForm = document.querySelector("form");
var loginButton = loginForm.querySelector('button[type="submit"]');
var loginBanner = document.getElementById("login-error");
var normalMessage = loginBanner.textContent;

loginForm.addEventListener("submit", async function (event) {
  event.preventDefault();
  loginBanner.hidden = true;

  var emailBox = document.getElementById("email");
  var passwordBox = document.getElementById("password");
  var email = emailBox.value.trim();
  var password = passwordBox.value;

  var badEmail = !/^\S+@\S+\.\S+$/.test(email);
  var badPassword = password === "";

  document.getElementById("email-error").hidden = !badEmail;
  emailBox.classList.toggle("input-error", badEmail);
  document.getElementById("password-error").hidden = !badPassword;
  passwordBox.classList.toggle("input-error", badPassword);

  if (badEmail || badPassword) {
    return;
  }

  loginButton.disabled = true;
  loginButton.textContent = "Logging in...";

  var result = await db.auth.signInWithPassword({ email: email, password: password });

  if (result.error) {
    loginButton.disabled = false;
    loginButton.textContent = "Login";

    if (result.error.message.indexOf("not confirmed") !== -1) {
      loginBanner.textContent = "Please open the link we emailed you to confirm your email, then login.";
    } else {
      loginBanner.textContent = normalMessage;
    }
    loginBanner.hidden = false;
    return;
  }

  goHome();
});
