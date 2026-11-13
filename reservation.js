// ===== My reservation page: show one real reservation =====

var reservationId = new URLSearchParams(window.location.search).get("id");
var holdEnds = null;

// "41h 12m" or "Hold ended"
function showTimer() {
  var minutes = Math.floor((holdEnds - Date.now()) / 60000);
  var timer = document.querySelector(".timer strong");
  if (minutes <= 0) {
    timer.textContent = "Ended";
    return;
  }
  timer.textContent = Math.floor(minutes / 60) + "h " + (minutes % 60) + "m";
}

var statusNames = {
  claimed: "Waiting for the owner",
  disputed: "Under review",
  credited: "Credit added",
  completed: "Completed",
  cancelled: "Cancelled"
};

async function showReservation() {
  await db.rpc("process_expired_holds");

  // Opened from the navbar (no id in the address): show the latest reservation
  if (!reservationId) {
    var latest = await db.from("reservations").select("id").neq("status", "credited").order("created_at", { ascending: false }).limit(1);
    reservationId = latest.data && latest.data[0] ? latest.data[0].id : null;
  }

  var result = await db.rpc("my_reservation", { p_id: reservationId });
  var item = result.data && result.data[0];

  if (!item) {
    document.querySelector(".res-layout").innerHTML =
      '<p class="muted">We could not find a reservation. <a href="dashboard.html#reservations" class="text-link">Back to my reservations</a></p>';
    return;
  }

  // The room
  var picture = document.querySelector(".res-room img");
  if (item.room_photo) {
    picture.src = photoUrl(item.room_photo);
  }
  var badge = document.querySelector(".res-tags .badge");
  if (item.badge) {
    badge.className = "badge badge-" + item.badge;
    badge.textContent = item.badge === "trusted" ? "Trusted" : "Verified";
  } else {
    badge.hidden = true;
  }
  document.querySelector(".res-tags .tag-grey").textContent = item.room_type || "Room";
  document.querySelector(".res-room h3").textContent = item.room_title;
  document.querySelector(".res-room .card-body > .muted").textContent = item.distance_min ? item.distance_min + " mins to campus" : item.room_area;
  document.querySelector(".res-room .price").firstChild.textContent = "₦" + Number(item.price).toLocaleString() + " ";
  document.querySelector(".res-owner strong").textContent = item.owner_name || "Owner";
  document.querySelector(".res-owner .muted").textContent = item.room_area || "";

  // Contact buttons
  var chat = document.querySelector(".res-room .btn-whatsapp");
  var link = whatsappLink(item.whatsapp, "Hello, I reserved \"" + item.room_title + "\" on CampusLodge.");
  if (link) {
    chat.href = link;
    chat.target = "_blank";
  } else {
    chat.hidden = true;
  }
  var call = document.querySelector(".res-room .btn-white");
  var phone = (item.call_number || "").replace(/[^\d+]/g, "");
  if (phone) {
    call.href = "tel:" + phone;
  } else {
    call.hidden = true;
  }

  // The steps and the rent
  document.querySelector(".res-step .muted").textContent = "₦5,000 paid. Receipt ref " + item.reference + ".";
  document.querySelector(".rent-box strong").textContent = "₦" + Number(item.price).toLocaleString();
  if (item.owner_account_number) {
    document.getElementById("owner-account").textContent =
      [item.owner_bank, item.owner_account_number, item.owner_account_name].filter(Boolean).join(", ");
  }

  // The timer, or the status when the hold is over
  if (item.status === "held") {
    holdEnds = new Date(item.expires_at);
    showTimer();
    setInterval(showTimer, 60000);
  } else {
    document.querySelector(".hold-chip").textContent = "Hold closed";
    document.querySelector(".timer span").textContent = "Status";
    document.querySelector(".timer strong").textContent = statusNames[item.status] || item.status;
    document.querySelector(".decision").hidden = true;
    document.querySelector(".decision-note").hidden = true;
    document.querySelector(".res-links").hidden = true;
    document.getElementById("pay-rent").hidden = true;
  }

  // How many credits the student has used this semester
  var count = await db.rpc("credits_this_semester");
  document.querySelector(".dislike-intro").textContent =
    "The owner confirms you did not take the room, then your ₦5,000 becomes credit. Credits used this semester: " +
    (count.data || 0) + " of 3.";
}

// "There is a problem": send the request for credit
var moreInfo = document.getElementById("more-info");
var bannerError = document.getElementById("dislike-error");
var moreError = document.getElementById("more-error");

document.getElementById("send-dislike").addEventListener("click", async function () {
  var chosen = document.querySelectorAll("#dislike-modal .reason input:checked");
  var wordsWritten = moreInfo.value.trim() !== "";

  bannerError.textContent = "Choose at least one reason and write a short explanation before you send.";
  bannerError.hidden = chosen.length > 0 && wordsWritten;
  moreError.hidden = wordsWritten;
  moreInfo.classList.toggle("input-error", !wordsWritten);

  if (chosen.length === 0 || !wordsWritten) {
    return;
  }

  var reasons = Array.from(chosen).map(function (box) {
    return box.parentNode.textContent.trim();
  });
  var result = await db.rpc("claim_credit", {
    p_res: reservationId,
    p_reasons: reasons,
    p_note: moreInfo.value
  });

  if (result.error) {
    bannerError.textContent = result.error.message;
    bannerError.hidden = false;
    return;
  }

  document.getElementById("dislike-modal").classList.remove("open");
  document.getElementById("sent-modal").classList.add("open");
});

// "Owner did not show up?": the admin looks at it
document.getElementById("send-problem").addEventListener("click", async function () {
  var chosen = document.querySelector('input[name="problem"]:checked');
  var info = document.getElementById("problem-info");
  var wordsWritten = info.value.trim() !== "";
  var banner = document.getElementById("problem-error");

  banner.hidden = chosen !== null && wordsWritten;
  document.getElementById("problem-info-error").hidden = wordsWritten;
  info.classList.toggle("input-error", !wordsWritten);
  if (!chosen || !wordsWritten) {
    return;
  }

  var result = await db.rpc("report_no_show", {
    p_res: reservationId,
    p_reason: chosen.parentNode.textContent.trim(),
    p_note: info.value
  });
  if (result.error) {
    banner.textContent = result.error.message;
    banner.hidden = false;
    return;
  }
  document.getElementById("problem-modal").classList.remove("open");
  document.getElementById("problem-sent-modal").classList.add("open");
});

// Cancel the reservation: the fee becomes credit
document.getElementById("confirm-cancel").addEventListener("click", async function () {
  var error = document.getElementById("cancel-error");
  var result = await db.rpc("cancel_reservation", { p_res: reservationId });
  if (result.error) {
    error.textContent = result.error.message;
    error.hidden = false;
    return;
  }
  window.location.href = "credit.html";
});

// "I have paid the rent"
document.getElementById("rent-paid").addEventListener("click", async function () {
  var error = document.getElementById("rent-error");
  var result = await db.rpc("mark_rent_paid", { p_res: reservationId });
  if (result.error) {
    error.textContent = result.error.message;
    error.hidden = false;
    return;
  }
  error.hidden = true;
  document.getElementById("key-modal").classList.add("open");
});

showReservation();
