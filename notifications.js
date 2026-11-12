// ===== Notifications page: real notifications =====
var noteIcons = {
  ok: "✓",
  money: "₦",
  alert: "⚠",
  room: "⌂",
  info: "i"
};

function timeAgo(text) {
  var minutes = Math.round((Date.now() - new Date(text).getTime()) / 60000);
  if (minutes < 1) { return "Just now"; }
  if (minutes < 60) { return minutes + " min ago"; }
  var hours = Math.round(minutes / 60);
  if (hours < 24) { return hours + "h ago"; }
  var days = Math.round(hours / 24);
  return days === 1 ? "Yesterday" : days + " days ago";
}

async function loadNotes() {
  var result = await db
    .from("notifications")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50);
  var notes = result.data || [];
  var list = document.getElementById("note-list");
  list.innerHTML = "";

  if (notes.length === 0) {
    var empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "Nothing yet. Important things will show up here.";
    list.appendChild(empty);
    return;
  }

  notes.forEach(function (note) {
    var link = document.createElement("a");
    link.href = note.link || "dashboard.html";
    link.className = "note" + (note.is_read ? "" : " unread");
    link.innerHTML =
      '<span class="note-icon"></span>' +
      '<span class="note-text"><strong></strong><span class="muted"></span></span>' +
      '<span class="note-time"></span>';
    link.querySelector(".note-icon").textContent = noteIcons[note.icon] || "i";
    link.querySelector("strong").textContent = note.title;
    link.querySelector(".muted").textContent = note.body || "";
    link.querySelector(".note-time").textContent = timeAgo(note.created_at);
    list.appendChild(link);
  });
}

document.getElementById("mark-read").addEventListener("click", async function () {
  await db.rpc("mark_notifications_read");
  document.querySelectorAll(".note.unread").forEach(function (note) {
    note.classList.remove("unread");
  });
  document.querySelectorAll(".nav-dot").forEach(function (dot) {
    dot.remove();
  });
});

loadNotes();
