// ===== Contact page: saves the message so the admin can read it =====
document.getElementById("send-contact").addEventListener("click", async function () {
  var button = this;
  var name = document.getElementById("c-name");
  var email = document.getElementById("c-email");
  var message = document.getElementById("c-message");
  var error = document.getElementById("contact-error");

  var missing = false;
  [name, email, message].forEach(function (box) {
    var empty = box.value.trim() === "";
    box.classList.toggle("input-error", empty);
    if (empty) {
      missing = true;
    }
  });
  if (missing) {
    error.textContent = "Please fill in your name, email and message.";
    error.hidden = false;
    return;
  }
  error.hidden = true;
  button.disabled = true;

  var result = await db.rpc("send_contact", {
    p_name: name.value,
    p_email: email.value,
    p_message: message.value
  });
  if (result.error) {
    error.textContent = result.error.message;
    error.hidden = false;
    button.disabled = false;
    return;
  }
  document.getElementById("contact-form").hidden = true;
  document.getElementById("contact-sent").hidden = false;
});
