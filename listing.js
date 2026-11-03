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
  document.getElementById("listing-content").hidden = false;
}

showRoom();
