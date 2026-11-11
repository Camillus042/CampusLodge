// ===== Shows the student's real credit in the navbar and credit boxes =====

var creditBalance = 0;

async function showCredit() {
  var result = await db.rpc("my_credit_balance");
  creditBalance = result.data || 0;
  var money = "₦" + creditBalance.toLocaleString();

  document.querySelectorAll(".credit-chip").forEach(function (chip) {
    chip.textContent = creditBalance > 0 ? money + " credit" : "No credit";
  });

  // The credit box on the dashboard
  document.querySelectorAll(".credit-strip").forEach(function (box) {
    box.hidden = creditBalance === 0;
    box.querySelector("h3").textContent = "You have " + money + " credit";
  });

  // The note on the listing page
  var note = document.querySelector(".credit-note");
  if (note) {
    note.hidden = creditBalance === 0;
    note.textContent = "You have " + money + " credit. You can use it at checkout.";
  }
}

showCredit();
