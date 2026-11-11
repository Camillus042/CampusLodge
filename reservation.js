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

async function showReservation() {
  var result = await db.rpc("my_reservation", { p_id: reservationId });
  var item = result.data && result.data[0];

  if (!item) {
    document.querySelector(".res-layout").innerHTML =
      '<p class="muted">We could not find that reservation. <a href="dashboard.html#reservations" class="text-link">Back to my reservations</a></p>';
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

  // The timer
  holdEnds = new Date(item.expires_at);
  showTimer();
  setInterval(showTimer, 60000);
}

showReservation();
