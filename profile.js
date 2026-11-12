// ===== Profile page: load and save the real details =====

var myRole = "";

// Shows the small "Saved" note for 3 seconds
function flashSaved(form) {
  var note = form.querySelector(".saved-note");
  note.hidden = false;
  setTimeout(function () {
    note.hidden = true;
  }, 3000);
}

// Shows or clears the red message in a form
function formError(form, text) {
  var box = form.querySelector(".error-text");
  box.textContent = text || "";
  box.hidden = !text;
}

async function loadProfile() {
  var result = await db.rpc("my_profile");
  var me = result.data && result.data[0];
  if (!me) {
    return;
  }
  myRole = me.role;

  document.getElementById("p-name").value = me.full_name || "";
  document.getElementById("p-email").value = me.email || "";
  document.getElementById("p-phone").value = me.phone || "";
  document.getElementById("p-matric").value = me.matric || "";
  document.getElementById("p-hostel").value = me.hostel_name || "";
  document.getElementById("bank").value = me.bank_name || "";
  document.getElementById("acct-number").value = me.account_number || "";
  document.getElementById("acct-name").value = me.account_name || "";
  document.getElementById("n-rooms").checked = me.notify_rooms;
  document.getElementById("n-tips").checked = me.notify_tips;

  // Show only the parts that belong to this person's role
  var isStudent = me.role === "student";
  document.getElementById("matric-field").hidden = !isStudent;
  document.getElementById("hostel-field").hidden = me.role !== "hostel";
  document.getElementById("payout").hidden = isStudent;
  document.getElementById("payout-link").hidden = isStudent;
}

// Personal details
document.getElementById("details-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var form = this;
  formError(form, "");
  var result = await db.rpc("save_profile", {
    p_name: document.getElementById("p-name").value,
    p_phone: document.getElementById("p-phone").value,
    p_matric: document.getElementById("p-matric").value,
    p_hostel: document.getElementById("p-hostel").value
  });
  if (result.error) {
    formError(form, result.error.message);
    return;
  }
  flashSaved(form);
});

// Password: check the old one, then set the new one
document.getElementById("password-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var form = this;
  var oldPassword = document.getElementById("old-password").value;
  var newPassword = document.getElementById("new-password").value;
  var confirmPassword = document.getElementById("confirm-password").value;

  if (oldPassword === "" || newPassword === "" || confirmPassword === "") {
    formError(form, "Fill in all three boxes.");
    return;
  }
  if (newPassword.length < 8) {
    formError(form, "The new password needs at least 8 characters.");
    return;
  }
  if (newPassword !== confirmPassword) {
    formError(form, "The two new passwords are not the same.");
    return;
  }
  formError(form, "");

  var email = document.getElementById("p-email").value;
  var check = await db.auth.signInWithPassword({ email: email, password: oldPassword });
  if (check.error) {
    formError(form, "Your current password is not correct.");
    return;
  }
  var update = await db.auth.updateUser({ password: newPassword });
  if (update.error) {
    formError(form, update.error.message);
    return;
  }
  form.reset();
  flashSaved(form);
});

// Payout account
document.getElementById("payout-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var form = this;
  formError(form, "");
  var result = await db.rpc("save_payout", {
    p_bank: document.getElementById("bank").value,
    p_number: document.getElementById("acct-number").value.trim(),
    p_name: document.getElementById("acct-name").value
  });
  if (result.error) {
    formError(form, result.error.message);
    return;
  }
  flashSaved(form);
});

// Notification settings
document.getElementById("notify-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var result = await db.rpc("save_notify", {
    p_rooms: document.getElementById("n-rooms").checked,
    p_tips: document.getElementById("n-tips").checked
  });
  if (!result.error) {
    flashSaved(this);
  }
});

// Delete pop-up: the red button only works after typing DELETE
var deleteModal = document.getElementById("delete-modal");
var deleteWord = document.getElementById("delete-word");
var confirmDelete = document.getElementById("confirm-delete");
var deleteError = document.getElementById("delete-error");

document.getElementById("open-delete").addEventListener("click", function () {
  deleteWord.value = "";
  confirmDelete.disabled = true;
  deleteError.hidden = true;
  deleteModal.classList.add("open");
});

deleteWord.addEventListener("input", function () {
  confirmDelete.disabled = deleteWord.value !== "DELETE";
});

confirmDelete.addEventListener("click", async function () {
  confirmDelete.disabled = true;
  var result = await db.rpc("delete_my_account");
  if (result.error) {
    deleteError.textContent = result.error.message;
    deleteError.hidden = false;
    confirmDelete.disabled = false;
    return;
  }
  await db.auth.signOut();
  window.location.href = "index.html";
});

document.querySelectorAll("[data-close]").forEach(function (button) {
  button.addEventListener("click", function () {
    document.getElementById(button.dataset.close).classList.remove("open");
  });
});

deleteModal.addEventListener("click", function (event) {
  if (event.target === deleteModal) {
    deleteModal.classList.remove("open");
  }
});

loadProfile();
