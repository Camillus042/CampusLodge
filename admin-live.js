// ===== Admin dashboard: real users, reports, disputes and fees =====

var allFees = [];

var reasonNames = {
  fake: "Looks fake or like a scam",
  wrong: "The price or photos are wrong",
  outside: "Owner asked to pay outside CampusLodge",
  taken: "The room is already taken",
  other: "Something else"
};

function shortDate(text) {
  return new Date(text).toLocaleDateString("en-NG", { day: "numeric", month: "short" });
}

// Makes one button that opens the pop-up (the pop-up code is in admin.html)
function makeAction(spec) {
  var button = document.createElement("button");
  button.type = "button";
  button.className = "small-btn act " + (spec.style || "");
  button.textContent = spec.text;
  button.dataset.title = spec.title;
  button.dataset.text = spec.message;
  button.dataset.button = spec.confirm;
  button.dataset.rpc = spec.rpc;
  button.dataset.args = JSON.stringify(spec.args);
  if (spec.label) {
    button.dataset.label = spec.label;
    button.dataset.reason = "yes";
    button.dataset.noteArg = "p_note";
  }
  if (spec.danger) {
    button.dataset.danger = "yes";
  }
  button.addEventListener("click", function () {
    openAction(button);
  });
  return button;
}

// Makes one row. Everything typed by users goes in with textContent.
function makeAdminRow(info) {
  var row = document.createElement("div");
  row.className = "admin-row" + (info.extraClass ? " " + info.extraClass : "");
  row.innerHTML =
    '<div class="row-main"><h3></h3><p class="muted sub"></p></div>' +
    '<div class="row-mid"><p class="line1"></p><p class="muted line2"></p></div>' +
    '<span class="chip"></span>' +
    '<div class="row-actions"></div>';
  row.querySelector("h3").textContent = info.title;
  row.querySelector(".sub").textContent = info.sub || "";
  row.querySelector(".line1").textContent = info.line1 || "";
  row.querySelector(".line2").textContent = info.line2 || "";
  var chip = row.querySelector(".chip");
  chip.textContent = info.chip;
  chip.className = "chip " + info.chipClass;
  (info.buttons || []).forEach(function (button) {
    row.querySelector(".row-actions").appendChild(button);
  });
  if (info.kind) {
    row.dataset.kind = info.kind;
    row.dataset.status = info.status;
  }
  return row;
}

function emptyMessage(box, text) {
  box.innerHTML = "";
  var message = document.createElement("p");
  message.className = "muted";
  message.textContent = text;
  box.appendChild(message);
}

// A Trusted / Verified switch that saves as soon as it is moved
function makeSwitch(label, on, userId, onAction, offAction) {
  var wrap = document.createElement("label");
  wrap.className = "switch-line";
  wrap.innerHTML = '<span class="switch"><input type="checkbox"><span class="switch-dot"></span></span>';
  wrap.appendChild(document.createTextNode(label));
  var box = wrap.querySelector("input");
  box.checked = on;
  box.addEventListener("change", async function () {
    var result = await db.rpc("admin_user_action", {
      p_user: userId,
      p_action: box.checked ? onAction : offAction
    });
    if (result.error) {
      alert("We could not save that. Please try again.");
    }
    refreshAdmin();
  });
  return wrap;
}

// ----- Users, Trusted listers and hostel managers -----
async function loadUsers() {
  var result = await db.rpc("admin_users");
  var users = result.data || [];

  var trustedBox = document.getElementById("trusted-list");
  var hostelBox = document.getElementById("hostel-list");
  var usersBox = document.getElementById("users-list");
  trustedBox.innerHTML = "";
  hostelBox.innerHTML = "";
  usersBox.innerHTML = "";

  var counts = { all: 0, student: 0, lister: 0, hostel: 0, banned: 0 };
  var waiting = 0;

  users.forEach(function (user) {
    var name = user.hostel_name || user.full_name;
    var kind = user.role === "student" ? "student" : user.role === "hostel" ? "hostel" : "lister";
    var banned = user.status === "banned";
    counts.all++;
    counts[kind]++;
    if (banned) {
      counts.banned++;
    }

    // Trusted badge for landlords and agents
    if (kind === "lister") {
      var trustedRow = makeAdminRow({
        title: user.full_name,
        sub: user.role === "agent" ? "Agent" : "Landlord",
        chip: user.trusted ? "Trusted" : "Not trusted",
        chipClass: user.trusted ? "chip-green" : "chip-grey"
      });
      trustedRow.querySelector(".row-mid").innerHTML = "";
      trustedRow.querySelector(".row-mid").appendChild(
        makeSwitch("Trusted", user.trusted, user.id, "trusted_on", "trusted_off")
      );
      trustedBox.appendChild(trustedRow);
    }

    // Approval and Verified badge for hostel managers
    if (kind === "hostel") {
      if (!user.approved) {
        waiting++;
      }
      var hostelRow = makeAdminRow({
        title: name,
        sub: user.full_name,
        chip: user.approved ? "Approved" : "Waiting for approval",
        chipClass: user.approved ? "chip-green" : "chip-orange"
      });
      hostelRow.querySelector(".row-mid").innerHTML = "";
      hostelRow.querySelector(".row-mid").appendChild(
        makeSwitch("Verified", user.approved, user.id, "approve", "unapprove")
      );
      hostelBox.appendChild(hostelRow);
    }

    // The full users list
    var roleNames = { student: "Student", landlord: "Landlord", agent: "Agent", hostel: "Hostel manager" };
    var line2 = "Warnings: " + user.warnings;
    if (kind === "student") {
      line2 += " · Credits used: " + user.credits_used + " of 3";
    } else {
      line2 += " · " + user.listing_count + " listing(s)";
    }
    var chipText = "Active";
    var chipClass = "chip-green";
    if (banned) {
      chipText = "Banned";
      chipClass = "chip-red";
    } else if (user.credit_frozen) {
      chipText = "Credit frozen";
      chipClass = "chip-orange";
    } else if (user.warnings > 0) {
      chipText = "Warned";
      chipClass = "chip-orange";
    }

    var buttons = [];
    if (banned) {
      buttons.push(makeAction({
        text: "Restore", style: "small-green", rpc: "admin_user_action",
        args: { p_user: user.id, p_action: "unban" },
        title: "Restore " + name + "?",
        message: "They can log in again and use the site as before.",
        confirm: "Restore"
      }));
    } else {
      buttons.push(makeAction({
        text: "Warn", rpc: "admin_user_action",
        args: { p_user: user.id, p_action: "warn" },
        title: "Warn " + name + "?",
        message: "This is the first step. The warning is recorded.",
        label: "Message to them", confirm: "Send warning"
      }));
      if (kind === "student") {
        buttons.push(makeAction({
          text: "Freeze credit", rpc: "admin_user_action",
          args: { p_user: user.id, p_action: "freeze" },
          title: "Freeze credit for " + name + "?",
          message: "They cannot use credit. They can still reserve rooms by paying.",
          label: "Reason (only admins see this)", confirm: "Freeze credit"
        }));
      }
      buttons.push(makeAction({
        text: kind === "student" ? "Ban" : "Ban and remove listings", style: "small-red",
        rpc: "admin_user_action", args: { p_user: user.id, p_action: "ban" },
        title: "Ban " + name + "?",
        message: kind === "student"
          ? "They cannot reserve rooms or use credit. You can restore them any time."
          : "All their listings are removed. Students who reserved their rooms get ₦5,000 back as credit.",
        label: "Reason (only admins see this)", confirm: "Ban account", danger: true
      }));
    }

    usersBox.appendChild(makeAdminRow({
      extraClass: "user-row",
      title: name,
      sub: user.email,
      line1: roleNames[user.role] + " · Joined " + shortDate(user.joined),
      line2: line2,
      chip: chipText,
      chipClass: chipClass,
      buttons: buttons,
      kind: kind,
      status: banned ? "banned" : "active"
    }));
  });

  if (trustedBox.children.length === 0) {
    emptyMessage(trustedBox, "No landlords or agents yet.");
  }
  if (hostelBox.children.length === 0) {
    emptyMessage(hostelBox, "No hostel managers yet.");
  }
  if (usersBox.children.length === 0) {
    emptyMessage(usersBox, "No users yet.");
  }

  // Numbers on the filter buttons and the top box
  var chips = { all: "All", student: "Students", lister: "Landlords and agents", hostel: "Hostel managers", banned: "Banned" };
  document.querySelectorAll('.filter-chip[data-list="users-list"]').forEach(function (chip) {
    chip.textContent = chips[chip.dataset.filter] + " " + counts[chip.dataset.filter];
  });
  document.getElementById("stat-hostels").textContent = waiting;
  filterList("users-list");
}

// ----- Reported listings -----
async function loadReports() {
  var result = await db.rpc("admin_reports");
  var items = result.data || [];
  var box = document.getElementById("reports-list");
  document.getElementById("stat-reports").textContent = items.length;
  box.innerHTML = "";
  if (items.length === 0) {
    emptyMessage(box, "No reported listings.");
    return;
  }
  items.forEach(function (item) {
    box.appendChild(makeAdminRow({
      title: item.listing_title,
      sub: item.owner_name,
      line1: reasonNames[item.reason] || item.reason,
      line2: (item.details ? "“" + item.details + "” · " : "") + item.report_count + " open report(s)",
      chip: "Reported",
      chipClass: "chip-red",
      buttons: [
        makeAction({
          text: "Take down", style: "small-red", rpc: "admin_report_action",
          args: { p_report: item.id, p_takedown: true },
          title: "Take this listing down?",
          message: "It disappears from the site at once. The lister sees your note.",
          label: "Note to the lister", confirm: "Take down", danger: true
        }),
        makeAction({
          text: "Dismiss", rpc: "admin_report_action",
          args: { p_report: item.id, p_takedown: false },
          title: "Dismiss this report?",
          message: "The listing stays live and the report is closed.",
          confirm: "Dismiss"
        })
      ]
    }));
  });
}

// ----- Credit requests the owner disagreed with -----
async function loadDisputes() {
  var result = await db.rpc("admin_disputes");
  var items = result.data || [];
  var box = document.getElementById("disputes-list");
  document.getElementById("stat-disputes").textContent = items.length;
  box.innerHTML = "";
  if (items.length === 0) {
    emptyMessage(box, "No credit requests are waiting for you.");
    return;
  }
  items.forEach(function (item) {
    box.appendChild(makeAdminRow({
      title: item.student_name + " vs " + (item.owner_name || "the owner"),
      sub: item.room_title,
      line1: "Student says: " + item.claim_reasons.join(", "),
      line2: "“" + item.claim_note + "”",
      chip: "Under review",
      chipClass: "chip-orange",
      buttons: [
        makeAction({
          text: "Approve credit", style: "small-green", rpc: "admin_resolve_claim",
          args: { p_res: item.id, p_grant: true },
          title: "Approve this credit?",
          message: item.student_name + " gets ₦5,000 credit.",
          confirm: "Approve credit"
        }),
        makeAction({
          text: "Decline", style: "small-red", rpc: "admin_resolve_claim",
          args: { p_res: item.id, p_grant: false },
          title: "Decline this credit?",
          message: "No credit is given. The student paid for the room.",
          confirm: "Decline", danger: true
        })
      ]
    }));
  });
}

// ----- Fees -----
var feeStatus = {
  claimed: ["Credit requested", "chip-orange"],
  disputed: ["Under review", "chip-red"],
  credited: ["Credited", "chip-grey"],
  completed: ["Kept (room taken)", "chip-green"],
  cancelled: ["Cancelled", "chip-grey"]
};

function setFeeCard(id, amount, note) {
  var number = document.getElementById(id);
  number.textContent = "₦" + amount.toLocaleString();
  number.nextElementSibling.textContent = note;
}

async function loadFees() {
  var result = await db.rpc("admin_fees");
  allFees = result.data || [];
  var box = document.getElementById("fees-list");
  box.innerHTML = "";

  var received = allFees.filter(function (f) { return f.paid_with === "demo"; });
  var held = allFees.filter(function (f) { return f.status === "held" && new Date(f.expires_at) > new Date(); });
  var kept = allFees.filter(function (f) { return f.status === "completed"; });
  var credited = allFees.filter(function (f) { return f.status === "credited"; });
  var used = allFees.filter(function (f) { return f.paid_with === "credit"; });

  setFeeCard("fee-received", received.length * 5000, received.length + " booking fees");
  setFeeCard("fee-held", held.length * 5000, held.length + " active holds");
  setFeeCard("fee-kept", kept.length * 5000, kept.length + " rooms taken");
  setFeeCard("fee-credited", credited.length * 5000, credited.length + " credits given");
  setFeeCard("fee-used", used.length * 5000, used.length + " credits spent");

  if (allFees.length === 0) {
    emptyMessage(box, "No booking fees yet.");
    return;
  }
  allFees.forEach(function (item) {
    var row = document.createElement("div");
    row.className = "admin-row fee-row";
    row.innerHTML =
      '<span data-label="Reference"><strong></strong></span>' +
      '<span data-label="Student"></span>' +
      '<span data-label="Room"></span>' +
      '<span data-label="Date"></span>' +
      '<span data-label="Fee"></span>' +
      '<span data-label="Status"><span class="chip"></span></span>';
    var cells = row.querySelectorAll(":scope > span");
    cells[0].querySelector("strong").textContent = item.reference;
    cells[1].textContent = item.student_name;
    cells[2].textContent = item.room_title;
    cells[3].textContent = shortDate(item.created_at);
    cells[4].textContent = "₦" + item.amount.toLocaleString() + (item.paid_with === "credit" ? " (credit)" : "");

    var info = feeStatus[item.status] || ["Held (48h)", "chip-orange"];
    if (item.status === "held" && new Date(item.expires_at) <= new Date()) {
      info = ["Hold ended", "chip-grey"];
    }
    var chip = cells[5].querySelector(".chip");
    chip.textContent = info[0];
    chip.className = "chip " + info[1];
    box.appendChild(row);
  });
}

// Export CSV: downloads the fee list
document.getElementById("export-csv").addEventListener("click", function () {
  var lines = [["Reference", "Student", "Room", "Date", "Fee", "Paid with", "Status"]];
  allFees.forEach(function (f) {
    lines.push([f.reference, f.student_name, f.room_title, shortDate(f.created_at), f.amount, f.paid_with, f.status]);
  });
  var csv = lines.map(function (line) {
    return line.map(function (cell) {
      return '"' + String(cell).replace(/"/g, '""') + '"';
    }).join(",");
  }).join("\n");

  var link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
  link.download = "campuslodge-fees.csv";
  link.click();
});

// Load everything again (also used after every admin action)
async function refreshAdmin() {
  await Promise.all([loadUsers(), loadReports(), loadDisputes(), loadFees()]);
}

refreshAdmin();
