// ===== Forgot password: sends the reset link =====
document.getElementById("forgot-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var email = document.getElementById("email").value.trim();
  var error = document.getElementById("forgot-error");
  var button = document.getElementById("forgot-button");

  if (email === "") {
    error.textContent = "Please enter your email.";
    error.hidden = false;
    return;
  }
  error.hidden = true;
  button.disabled = true;

  var result = await db.auth.resetPasswordForEmail(email, {
    redirectTo: SITE_URL + "reset-password.html"
  });

  if (result.error) {
    error.textContent = "We could not send the email now. Please try again in a few minutes.";
    error.hidden = false;
    button.disabled = false;
    return;
  }
  // The same message whether or not the email has an account
  document.getElementById("forgot-form").hidden = true;
  document.getElementById("forgot-sent").hidden = false;
});
