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

// ===== The small dot beside "Notifications" when something is unread =====
async function showNotificationDot() {
  var result = await db
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("is_read", false);
  var unread = result.count || 0;

  document.querySelectorAll('a[href="notifications.html"]').forEach(function (link) {
    var dot = link.querySelector(".nav-dot");
    if (unread === 0 && dot) {
      dot.remove();
    }
    if (unread > 0 && !dot) {
      var newDot = document.createElement("span");
      newDot.className = "nav-dot";
      link.appendChild(newDot);
    }
  });
}

showNotificationDot();

// ===== Top bar for owners and hostel managers (pages that students share with them) =====
function showListerNavbar() {
  document.querySelectorAll(".student-only").forEach(function (item) {
    item.hidden = true;
  });
  var logo = document.getElementById("top-logo");
  if (logo) {
    logo.href = "lister.html";
  }
  var nav = document.querySelector(".navbar-links");
  var userLink = nav.querySelector(".nav-user");
  [
    ["My listings", "lister.html"],
    ["Add listing", "add-listing.html"],
    ["Verification", "lister.html#verify"],
    ["Notifications", "notifications.html"]
  ].forEach(function (item) {
    var link = document.createElement("a");
    link.className = "nav-link";
    link.href = item[1];
    link.textContent = item[0];
    if (window.location.pathname.indexOf(item[1]) !== -1) {
      link.className += " nav-active";
    }
    nav.insertBefore(link, userLink);
  });
  showNotificationDot();
}
