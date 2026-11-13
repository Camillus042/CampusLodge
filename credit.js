// ===== My credit page: the real balance and history =====

var creditReasons = {
  expired: "Your 48-hour hold ended.",
  did_not_like: "The owner confirmed you did not take the room.",
  admin: "The admin approved your request.",
  cancelled: "You cancelled the reservation.",
  no_show: "The admin approved your report."
};

function creditDate(text) {
  return new Date(text).toLocaleDateString("en-NG", { day: "numeric", month: "short" });
}

// One line of the history
function makeHistoryRow(plus, title, text, amount) {
  var row = document.createElement("div");
  row.className = "history-row";
  row.innerHTML =
    '<span class="history-icon"></span>' +
    '<div class="history-info"><strong></strong><p class="muted"></p></div>' +
    '<strong></strong>';
  var icon = row.querySelector(".history-icon");
  icon.className = "history-icon " + (plus ? "icon-plus" : "icon-minus");
  icon.textContent = plus ? "+" : "−";
  row.querySelector(".history-info strong").textContent = title;
  row.querySelector(".history-info .muted").textContent = text;
  var money = row.lastChild;
  money.className = plus ? "amount-plus" : "amount-minus";
  money.textContent = (plus ? "+" : "−") + "₦" + amount.toLocaleString();
  return row;
}

async function showCreditPage() {
  var credits = await db.from("credits").select("*").order("created_at", { ascending: false });
  var reservations = await db.from("reservations").select("id, room_title");
  var rooms = {};
  (reservations.data || []).forEach(function (item) {
    rooms[item.id] = item.room_title;
  });

  var list = credits.data || [];
  var balance = 0;
  var box = document.getElementById("history-list");
  box.innerHTML = "";

  list.forEach(function (credit) {
    if (credit.status === "available") {
      balance += credit.amount;
    }
    if (credit.used_reservation_id) {
      box.appendChild(makeHistoryRow(
        false,
        "Credit used",
        "Applied to " + (rooms[credit.used_reservation_id] || "a room") + ".",
        credit.amount
      ));
    }
    box.appendChild(makeHistoryRow(
      true,
      "Credit added",
      (rooms[credit.reservation_id] || "A room") + ". " + (creditReasons[credit.reason] || "") + " " + creditDate(credit.created_at) + ".",
      credit.amount
    ));
  });

  document.getElementById("balance-amount").textContent = "₦" + balance.toLocaleString();
  document.querySelector(".history").hidden = list.length === 0;
  document.querySelector(".no-credit").hidden = list.length !== 0;
}

showCreditPage();
