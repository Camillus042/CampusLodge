// ===== Dashboard: Available lodges =====

var allRooms = [];
var shown = 12;

// Keep only the rooms that match the three filters, newest first
function matchingRooms() {
  var area = document.getElementById("area").value;
  var type = document.getElementById("type").value;
  var price = Number(document.getElementById("price").value.replace(/\D/g, ""));

  return allRooms
    .filter(function (room) {
      if (area !== "Any area" && room.area !== area) {
        return false;
      }
      if (type !== "Any room type" && room.room_type !== type) {
        return false;
      }
      if (price && room.price > price) {
        return false;
      }
      return true;
    })
    .sort(function (a, b) {
      return new Date(b.created_at) - new Date(a.created_at);
    });
}

function showRooms() {
  var box = document.getElementById("recommended-grid");
  var rooms = matchingRooms();
  box.innerHTML = "";

  if (rooms.length === 0) {
    box.innerHTML = '<p class="muted">No lodges match yet. Try changing the filters.</p>';
  }
  rooms.slice(0, shown).forEach(function (room) {
    box.appendChild(makeCard(room));
  });

  document.getElementById("show-more").hidden = shown >= rooms.length;
}

async function loadDashboard() {
  var result = await db.rpc("live_rooms");
  allRooms = result.data || [];
  showRooms();
}

// Search button
document.getElementById("search-form").addEventListener("submit", function (event) {
  event.preventDefault();
  shown = 12;
  showRooms();
  document.getElementById("available").scrollIntoView();
});

// Area tags choose that area in the filter
document.querySelectorAll(".area-tag").forEach(function (tag) {
  tag.addEventListener("click", function () {
    document.getElementById("area").value = tag.textContent.trim();
    shown = 12;
    showRooms();
  });
});

// Show more button
document.getElementById("show-more").addEventListener("click", function () {
  shown = shown + 12;
  showRooms();
});

loadDashboard();
