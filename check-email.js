// ===== Check your email: show the address and let people resend the link =====
var sentEmail = sessionStorage.getItem("signupEmail");
var emailSpot = document.getElementById("sent-email");
var resendLink = document.getElementById("resend");

if (sentEmail) {
  emailSpot.textContent = sentEmail;
}

resendLink.addEventListener("click", async function (event) {
  event.preventDefault();

  if (!sentEmail) {
    window.location.href = "signup.html";
    return;
  }

  var result = await db.auth.resend({
    type: "signup",
    email: sentEmail,
    options: { emailRedirectTo: SITE_URL + "login.html" }
  });

  if (result.error) {
    resendLink.textContent = "Please wait a minute, then try again";
  } else {
    resendLink.textContent = "Sent again. Check your inbox";
  }
});
