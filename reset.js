// ===== Reset password: the page the email link opens =====
// Supabase reads the link and logs the person in for a moment, so we can set the new password.
document.getElementById("reset-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var newPassword = document.getElementById("new-password").value;
  var confirmPassword = document.getElementById("confirm-password").value;
  var error = document.getElementById("reset-error");

  if (newPassword.length < 8) {
    error.textContent = "The password needs at least 8 characters.";
    error.hidden = false;
    return;
  }
  if (newPassword !== confirmPassword) {
    error.textContent = "The two passwords are not the same.";
    error.hidden = false;
    return;
  }

  var result = await db.auth.updateUser({ password: newPassword });
  if (result.error) {
    error.textContent = "This link has expired or was already used. Please ask for a new one.";
    error.hidden = false;
    return;
  }
  await db.auth.signOut();
  document.getElementById("reset-form-box").hidden = true;
  document.getElementById("reset-done").hidden = false;
});
