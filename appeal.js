// ===== Appeal page: only for banned people =====
var appealText = document.getElementById("appeal-text");
var appealError = document.getElementById("appeal-error");

function showSent() {
  document.getElementById("appeal-form").hidden = true;
  document.getElementById("appeal-sent").hidden = false;
}

async function startAppeal() {
  var userResult = await db.auth.getUser();
  if (!userResult.data.user) {
    window.location.href = "login.html";
    return;
  }
  var result = await db.rpc("my_ban_info");
  var info = result.data && result.data[0];
  if (!info) {
    // Not banned (or restored): send them to their normal page
    goHome();
    return;
  }
  document.getElementById("ban-reason").textContent = info.reason;
  if (info.appeal_sent) {
    showSent();
  }
}

document.getElementById("send-appeal").addEventListener("click", async function () {
  var button = this;
  if (appealText.value.trim() === "") {
    appealError.textContent = "Please write a few words first.";
    appealError.hidden = false;
    appealText.classList.add("input-error");
    return;
  }
  button.disabled = true;
  var result = await db.rpc("send_appeal", { p_text: appealText.value });
  if (result.error) {
    appealError.textContent = result.error.message;
    appealError.hidden = false;
    button.disabled = false;
    return;
  }
  showSent();
});

// Log out link
document.getElementById("appeal-logout").addEventListener("click", async function (event) {
  event.preventDefault();
  await db.auth.signOut();
  window.location.href = "index.html";
});

startAppeal();
