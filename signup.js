// ===== Sign up: check the boxes, then create the account in Supabase =====
var signupForm = document.querySelector("form");
var signupButton = signupForm.querySelector('button[type="submit"]');
var signupBanner = document.getElementById("signup-error");

// Each account type uses its own letter in the box ids (s-name, l-name, h-name)
var letters = { student: "s", landlord: "l", hostel: "h" };

// Show or hide one error message and mark its box red
function setError(id, boxId, bad) {
  document.getElementById(id).hidden = !bad;
  document.getElementById(boxId).classList.toggle("input-error", bad);
  return bad;
}

// Turn 0801 234 5678 or +234 801 234 5678 into 08012345678
function cleanPhone(text) {
  var digits = text.replace(/[^0-9+]/g, "");
  if (digits.indexOf("+234") === 0) {
    digits = "0" + digits.slice(4);
  } else if (digits.indexOf("234") === 0) {
    digits = "0" + digits.slice(3);
  }
  return digits;
}

signupForm.addEventListener("submit", async function (event) {
  event.preventDefault();
  signupBanner.hidden = true;

  var type = document.querySelector('input[name="account-type"]:checked').value;
  var p = letters[type];

  var name = document.getElementById(p + "-name").value.trim();
  var phone = cleanPhone(document.getElementById(p + "-phone").value);
  var email = document.getElementById(p + "-email").value.trim();
  var password = document.getElementById(p + "-password").value;
  var confirm = document.getElementById(p + "-confirm").value;

  // Check every box. A "true" means that box has a problem.
  var problems = [
    setError(p + "-name-error", p + "-name", name === ""),
    setError(p + "-phone-error", p + "-phone", !/^0\d{10}$/.test(phone)),
    setError(p + "-email-error", p + "-email", !/^\S+@\S+\.\S+$/.test(email)),
    setError(p + "-password-error", p + "-password", password.length < 8),
    setError(p + "-confirm-error", p + "-confirm", confirm !== password)
  ];

  // Hostel managers also give the hostel name
  var hostelName = "";
  var hostelGender = "";
  if (type === "hostel") {
    hostelName = document.getElementById("h-hostel").value.trim();
    hostelGender = document.getElementById("h-gender").value;
    problems.push(setError("h-hostel-error", "h-hostel", hostelName === ""));
  }

  // The agreement tick box
  var agree = document.getElementById("agree");
  problems.push(setError("agree-error", "agree", !agree.checked));

  if (problems.indexOf(true) !== -1) {
    return;
  }

  // What kind of lister? The drop-down says Landlord or Agent
  var role = type;
  if (type === "landlord") {
    role = document.getElementById("l-role").value.toLowerCase();
  }

  signupButton.disabled = true;
  signupButton.textContent = "Creating account...";

  var result = await db.auth.signUp({
    email: email,
    password: password,
    options: {
      emailRedirectTo: SITE_URL + "login.html",
      data: {
        role: role,
        full_name: name,
        phone: phone,
        hostel_name: hostelName,
        hostel_gender: hostelGender,
        agreed: "true"
      }
    }
  });

  signupButton.disabled = false;
  signupButton.textContent = "Create account";

  // Supabase hides whether an email is taken. An empty "identities" list means it is.
  var user = result.data.user;
  var emailTaken = user && user.identities && user.identities.length === 0;

  if (result.error || emailTaken) {
    signupBanner.textContent = "We could not create the account. The email or phone number may already be used. Try logging in instead.";
    signupBanner.hidden = false;
    return;
  }

  // If email confirmation is switched off, the person is already logged in
  if (result.data.session) {
    goHome();
    return;
  }

  // Otherwise they must open the link we emailed them
  sessionStorage.setItem("signupEmail", email);
  window.location.href = "check-email.html";
});
