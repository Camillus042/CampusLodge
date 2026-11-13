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

// ===== My reservations =====

function formatDate(text) {
  return new Date(text).toLocaleString("en-NG", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

// Words for each status
var statusNames = {
  claimed: "Waiting for the owner",
  disputed: "Under review, up to 24 hours",
  credited: "Credit added",
  completed: "Completed",
  cancelled: "Cancelled"
};

// "Held, 41h left" or "Hold ended"
function holdText(item) {
  if (item.status !== "held") {
    return statusNames[item.status] || item.status;
  }
  var hours = Math.ceil((new Date(item.expires_at) - Date.now()) / 3600000);
  return hours > 0 ? "Held, " + hours + "h left" : "Hold ended";
}

// Fill the receipt pop-up and open it
function openReceipt(item) {
  document.getElementById("r-ref").textContent = item.reference;
  document.getElementById("r-date").textContent = formatDate(item.created_at);
  document.getElementById("r-student").textContent = document.querySelector('[data-user="first"]').textContent;
  document.getElementById("r-room").textContent = item.room_title;
  document.getElementById("r-owner").textContent = item.owner_name || "Owner";
  document.getElementById("receipt-modal").classList.add("open");
}

function makeReservation(item) {
  var row = document.createElement("div");
  row.className = "reservation";
  row.innerHTML =
    '<div class="photo-box"><img alt=""></div>' +
    '<div class="reservation-info"><h3></h3><p class="muted"></p></div>' +
    '<div class="fee">₦5,000<span>Booking fee</span></div>' +
    '<span class="status"></span>' +
    '<button type="button" class="btn btn-white">View receipt</button>' +
    '<a class="btn btn-green">Open</a>';

  var photo = row.querySelector("img");
  if (item.room_photo) {
    photo.src = photoUrl(item.room_photo);
  } else {
    photo.hidden = true;
  }
  row.querySelector("h3").textContent = item.room_title;
  row.querySelector(".muted").textContent = "Paid on " + formatDate(item.created_at) + " · Ref " + item.reference;
  row.querySelector(".status").textContent = holdText(item);
  row.querySelector("button").addEventListener("click", function () {
    openReceipt(item);
  });
  row.querySelector("a").href = "reservation.html?id=" + item.id;
  return row;
}

async function loadReservations() {
  var result = await db.from("reservations").select("*").neq("status", "credited").order("created_at", { ascending: false });
  var list = document.getElementById("reservation-list");
  var items = result.data || [];
  list.innerHTML = "";

  if (items.length === 0) {
    list.innerHTML = '<p class="muted">You have no reservations yet. Pick a lodge above and tap Rent.</p>';
  }
  items.forEach(function (item) {
    list.appendChild(makeReservation(item));
  });
}

// Holds that ended turn into credit first, then everything loads
async function startDashboard() {
  await db.rpc("process_expired_holds");
  loadDashboard();
  loadReservations();
}

startDashboard();
