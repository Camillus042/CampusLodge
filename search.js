// ===== Search page: show the real rooms =====

var allRooms = [];
var grid = document.getElementById("results-grid");

// The text of the chosen button in a group, for example "Self-contain"
function pickedText(name) {
  return document.querySelector('input[name="' + name + '"]:checked').parentNode.textContent.trim();
}

// Keep only the rooms that match the filters
function filterRooms() {
  var area = document.getElementById("area").value;
  var roomType = pickedText("room-type");
  var price = pickedText("price");
  var distance = pickedText("distance");
  var gender = pickedText("gender");
  var maxPrice = price === "Any" ? 0 : Number(price.replace(/\D/g, ""));

  var wanted = [];
  document.querySelectorAll(".filters .amenity input:checked").forEach(function (box) {
    wanted.push(box.parentNode.textContent.trim());
  });

  return allRooms.filter(function (room) {
    if (area !== "Any area" && room.area !== area) {
      return false;
    }
    if (roomType !== "Any" && room.room_type !== roomType) {
      return false;
    }
    if (maxPrice && room.price > maxPrice) {
      return false;
    }
    if (distance === "On campus" && room.area !== "Inside campus") {
      return false;
    }
    if (distance === "Under 10 mins" && !(room.distance_min !== null && room.distance_min < 10)) {
      return false;
    }
    if (distance === "10 to 20 mins" && !(room.distance_min >= 10 && room.distance_min <= 20)) {
      return false;
    }
    if (gender !== "Any" && (room.hostel_gender || "").toLowerCase() !== gender.toLowerCase()) {
      return false;
    }
    for (var i = 0; i < wanted.length; i++) {
      if (room.amenities.indexOf(wanted[i]) === -1) {
        return false;
      }
    }
    return true;
  });
}

// Put the rooms in the chosen order
function sortRooms(rooms) {
  var how = document.querySelector('select[aria-label="Sort"]').value;
  function howFar(room) {
    if (room.area === "Inside campus") {
      return 0;
    }
    return room.distance_min === null ? 9999 : room.distance_min;
  }
  return rooms.sort(function (a, b) {
    if (how === "Price: low to high") {
      return a.price - b.price;
    }
    if (how === "Price: high to low") {
      return b.price - a.price;
    }
    if (how === "Closest to campus") {
      return howFar(a) - howFar(b);
    }
    return new Date(b.created_at) - new Date(a.created_at);
  });
}

function makeCard(room) {
  var card = document.createElement("article");
  card.className = "card";
  card.innerHTML =
    '<div class="photo-box"><img alt="">' +
    '<span class="badge" hidden></span>' +
    '<button type="button" class="save-button" aria-label="Save listing">&#9825;</button></div>' +
    '<div class="card-body"><h3></h3><p class="muted"></p><div class="tags"></div>' +
    '<p class="price">₦' + Number(room.price).toLocaleString() + ' <span>/ year</span></p>' +
    '<div class="card-buttons">' +
    '<a class="btn btn-dark">Details</a>' +
    '<a class="btn btn-whatsapp" target="_blank">WhatsApp</a></div></div>';

  var picture = card.querySelector("img");
  picture.src = room.photos.length > 0 ? photoUrl(room.photos[0]) : "images/room-1.svg";
  picture.alt = room.title;

  var badge = card.querySelector(".badge");
  if (room.badge === "trusted" || room.badge === "verified") {
    badge.hidden = false;
    badge.className = "badge badge-" + room.badge;
    badge.textContent = room.badge === "trusted" ? "Trusted" : "Verified";
  }

  card.querySelector("h3").textContent = room.title;
  var place = [room.area];
  if (room.distance_min) {
    place.push(room.distance_min + " mins to campus");
  }
  card.querySelector(".muted").textContent = place.filter(Boolean).join(" · ");

  room.amenities.slice(0, 3).forEach(function (name) {
    var tag = document.createElement("span");
    tag.textContent = name;
    card.querySelector(".tags").appendChild(tag);
  });

  card.querySelector(".btn-dark").href = "listing.html?id=" + room.id;

  var chat = card.querySelector(".btn-whatsapp");
  var link = whatsappLink(room.whatsapp, "Hello, I saw your listing \"" + room.title + "\" on CampusLodge.");
  if (link) {
    chat.href = link;
  } else {
    chat.hidden = true;
  }
  return card;
}

function showRooms() {
  var rooms = sortRooms(filterRooms());
  var count = rooms.length;
  document.getElementById("result-count").textContent =
    (count === 1 ? "1 listing" : count + " listings") + " found near AKSU";

  grid.innerHTML = "";
  if (count === 0) {
    grid.innerHTML = '<p class="muted">No rooms match yet. Try changing the filters.</p>';
  }
  rooms.forEach(function (room) {
    grid.appendChild(makeCard(room));
  });
}

async function loadRooms() {
  var result = await db.rpc("live_rooms");
  if (result.error) {
    grid.innerHTML = '<p class="muted">We could not load the rooms. Please refresh the page.</p>';
    return;
  }
  allRooms = result.data || [];
  showRooms();
}

document.getElementById("apply-filters").addEventListener("click", function () {
  showRooms();
  document.getElementById("filter-toggle").checked = false;
});
document.querySelector('select[aria-label="Sort"]').addEventListener("change", showRooms);

loadRooms();
