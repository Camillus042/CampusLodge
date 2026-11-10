// ===== Shared room card =====
// Used by the dashboard.

// One room card
function makeCard(room) {
  var card = document.createElement("article");
  card.className = "card";
  card.innerHTML =
    '<div class="photo-box"><img alt="">' +
    '<span class="badge" hidden></span></div>' +
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
