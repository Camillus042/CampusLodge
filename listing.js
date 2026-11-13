// ===== Listing page: show one real room =====

var roomId = new URLSearchParams(window.location.search).get("id");
var roleNames = { landlord: "Landlord", agent: "Agent", hostel: "Hostel manager" };

// "This week", "3 days ago"...
function timeAgo(dateText) {
  var days = Math.floor((Date.now() - new Date(dateText)) / 86400000);
  if (days < 1) {
    return "Today";
  }
  if (days === 1) {
    return "Yesterday";
  }
  if (days < 30) {
    return days + " days ago";
  }
  return Math.floor(days / 30) + " month(s) ago";
}

function fillRoom(room) {
  // Photos: the first one is big. Tap a photo to see it full size.
  var gallery = document.getElementById("gallery");
  gallery.innerHTML = "";
  gallery.className = "gallery gallery-" + Math.min(room.photos.length || 1, 5);
  var paths = room.photos.length > 0 ? room.photos : [null];
  paths.forEach(function (path, index) {
    var box = document.createElement("div");
    box.className = index === 0 ? "photo-box gallery-main" : "photo-box";
    var link = document.createElement("a");
    var picture = document.createElement("img");
    picture.alt = "Room photo " + (index + 1);
    if (path) {
      picture.src = photoUrl(path);
      link.href = photoUrl(path);
      link.target = "_blank";
    } else {
      picture.src = "images/room-1.svg";
    }
    link.appendChild(picture);
    box.appendChild(link);
    if (index === 0 && (room.badge === "trusted" || room.badge === "verified")) {
      var badge = document.createElement("span");
      badge.className = "badge badge-" + room.badge;
      badge.textContent = room.badge === "trusted" ? "Trusted owner" : "Verified hostel";
      box.appendChild(badge);
    }
    gallery.appendChild(box);
  });

  // Title: the last part after the comma is green
  var heading = document.getElementById("listing-h1");
  var parts = room.title.split(",");
  heading.textContent = "";
  if (parts.length > 1) {
    heading.appendChild(document.createTextNode(parts.slice(0, -1).join(",") + ", "));
    var green = document.createElement("span");
    green.className = "green-word";
    green.textContent = parts[parts.length - 1].trim();
    heading.appendChild(green);
  } else {
    heading.textContent = room.title;
  }
  document.title = room.title + " | CampusLodge";

  var place = [room.area];
  if (room.distance_min) {
    place.push(room.distance_min + " mins to campus");
  }
  document.getElementById("listing-place").textContent = place.filter(Boolean).join(", ");

  // The four small facts
  document.getElementById("fact-type").textContent = room.room_type || "Room";
  document.getElementById("fact-distance").textContent =
    room.area === "Inside campus" ? "Inside campus" : room.distance_min ? room.distance_min + " mins" : "Not given";
  document.getElementById("fact-posted").textContent = timeAgo(room.created_at);
  if (room.kind === "hostel") {
    var gender = room.hostel_gender ? room.hostel_gender.charAt(0).toUpperCase() + room.hostel_gender.slice(1) : "";
    var beds = room.beds ? room.beds + (room.beds === 1 ? " bed" : " beds") : "";
    document.getElementById("fact-hostel").textContent = [gender, beds].filter(Boolean).join(", ");
    document.getElementById("fact-hostel-box").hidden = false;
  }

  document.getElementById("about-text").textContent =
    room.description || "The owner has not added a description yet.";

  var amenityBox = document.getElementById("amenity-grid");
  amenityBox.innerHTML = "";
  if (room.amenities.length === 0) {
    amenityBox.innerHTML = '<p class="muted">No amenities listed.</p>';
  }
  room.amenities.forEach(function (name) {
    var item = document.createElement("div");
    item.className = "amenity-item";
    item.innerHTML = '<span class="tick">&#10003;</span>';
    item.appendChild(document.createTextNode(name));
    amenityBox.appendChild(item);
  });

  var rent = document.getElementById("rent");
  rent.insertBefore(document.createTextNode("₦" + Number(room.price).toLocaleString() + " "), rent.firstChild);

  // Contact buttons
  var chat = document.getElementById("contact-whatsapp");
  var link = whatsappLink(room.whatsapp, "Hello, I saw your listing \"" + room.title + "\" on CampusLodge.");
  if (link) {
    chat.href = link;
    chat.target = "_blank";
  } else {
    chat.hidden = true;
  }
  var call = document.getElementById("contact-call");
  var phone = (room.call_number || "").replace(/[^\d+]/g, "");
  if (phone) {
    call.href = "tel:" + phone;
  } else {
    call.hidden = true;
  }

  // The owner
  var ownerName = room.owner_name || "Owner";
  document.getElementById("owner-avatar").textContent = ownerName.charAt(0).toUpperCase();
  document.getElementById("owner-name").textContent = ownerName;
  var ownerText = roleNames[room.owner_role] || "Owner";
  if (room.badge === "trusted") {
    ownerText = ownerText + ", ID and proof checked";
  }
  document.getElementById("owner-text").textContent = ownerText;
  var ownerBadge = document.getElementById("owner-badge");
  if (room.badge === "trusted" || room.badge === "verified") {
    ownerBadge.className = "badge badge-" + room.badge;
    ownerBadge.textContent = room.badge === "trusted" ? "Trusted" : "Verified";
    ownerBadge.hidden = false;
  }
}

async function showRoom() {
  var result = await db.rpc("live_rooms");
  var rooms = result.data || [];
  var room = rooms.find(function (item) {
    return item.id === roomId;
  });

  if (!room) {
    document.getElementById("listing-missing").hidden = false;
    return;
  }
  fillRoom(room);
  fillPayment(room);
  document.getElementById("listing-content").hidden = false;
}

showRoom();

// ===== Reserve this room (demo payment) =====

function formatDate(text) {
  return new Date(text).toLocaleString("en-NG", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

var currentRoom = null;

// Put the real room into the payment box
function fillPayment(room) {
  currentRoom = room;
  var box = document.querySelector("#payment-modal .pay-room");
  var picture = box.querySelector("img");
  if (room.photos && room.photos.length > 0) {
    picture.src = photoUrl(room.photos[0]);
  }
  box.querySelector("strong").textContent = room.title;
  box.querySelector(".muted").textContent = room.area;
  box.querySelector(".price").textContent = "₦" + Number(room.price).toLocaleString() + " / year";

  // Show "Use my credit" only when the student has credit
    db.rpc("my_credit_balance").then(function (result) {
    var amount = result.data || 0;
    var box = document.querySelector(".use-credit");
    box.hidden = amount === 0;
    box.querySelector("span").textContent = "Available: ₦" + amount.toLocaleString() + ". Reserve at ₦0.";
  });
}

// A place for error messages inside the payment box
var payError = document.createElement("p");
payError.className = "error-text";
payError.hidden = true;
document.querySelector("#payment-modal .modal-body").appendChild(payError);

// The Pay button
document.getElementById("pay-button").addEventListener("click", async function () {
  var button = document.getElementById("pay-button");
  payError.hidden = true;
  button.disabled = true;
  button.textContent = "Processing...";

  // A short pause so the demo feels like a real payment
  await new Promise(function (done) {
    setTimeout(done, 1200);
  });

  var result = await db.rpc("reserve_room", {
  p_listing: currentRoom.id,
  p_use_credit: document.getElementById("use-credit").checked
  });
  button.disabled = false;
  button.textContent = "Pay ₦5,000 (demo)";

  if (result.error) {
    payError.textContent = result.error.message;
    payError.hidden = false;
    return;
  }

  // Fill the receipt with the real reservation
  var reservation = result.data;
  var lines = document.querySelectorAll("#receipt-modal .receipt-line strong");
  lines[0].textContent = reservation.reference;
  lines[1].textContent = formatDate(reservation.created_at);
  lines[3].textContent = reservation.room_title;
  lines[4].textContent = reservation.owner_name || "Owner";
  lines[5].textContent = reservation.paid_with === "credit" ? "₦5,000 (paid with credit)" : "₦5,000";

  var message = document.querySelector("#receipt-modal .btn-whatsapp");
  var link = whatsappLink(currentRoom.whatsapp, "Hello, I have reserved \"" + currentRoom.title + "\" on CampusLodge.");
  if (link) {
    message.href = link;
    message.target = "_blank";
  } else {
    message.hidden = true;
  }
  document.querySelector("#receipt-modal .btn-dark").href = "reservation.html?id=" + reservation.id;

  document.getElementById("payment-modal").classList.remove("open");
  document.getElementById("receipt-modal").classList.add("open");
});

// ===== Report this listing =====
document.getElementById("send-report").addEventListener("click", async function () {
  var chosen = document.querySelector('input[name="report"]:checked');
  var error = document.getElementById("report-error");

  if (!chosen) {
    error.textContent = "Pick one reason first.";
    error.hidden = false;
    return;
  }

  var result = await db.rpc("report_listing", {
    p_listing: roomId,
    p_reason: chosen.value,
    p_details: document.getElementById("report-details").value
  });

  if (result.error) {
    error.textContent = result.error.message;
    error.hidden = false;
    return;
  }

  error.hidden = true;
  document.getElementById("report-modal").classList.remove("open");
  document.getElementById("report-sent-modal").classList.add("open");
});
