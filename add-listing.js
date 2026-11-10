// ===== Add listing: save the room to Supabase =====

var addForm = document.getElementById("add-form");
var formError = document.getElementById("form-error");

function showFormError(message) {
  formError.textContent = message;
  formError.hidden = false;
  window.scrollTo(0, 0);
}

// "230,000" becomes 230000. Returns 0 if it is not a number.
function toNumber(text) {
  var number = Number(text.replace(/[,\s]/g, ""));
  if (isNaN(number) || number < 0) {
    return 0;
  }
  return Math.round(number);
}

// Hostel managers list campus hostels, everyone else lists apartments.
// The hostel part of the form (gender, beds) only shows for hostel managers.
var isHostel = false;
var hostelSection = document.getElementById("hostel-section");

async function findAccountType() {
  var userResult = await db.auth.getUser();
  var result = await db
    .from("profiles")
    .select("role")
    .eq("id", userResult.data.user.id)
    .single();
  isHostel = result.data.role === "hostel";
  hostelSection.hidden = !isHostel;

  // Hostel rooms are always shared rooms inside the campus
  if (isHostel) {
    document.getElementById("room-type").innerHTML = "<option>Shared room</option>";
    document.getElementById("area").innerHTML = "<option>Inside campus</option>";
  }
}

// Editing: the page address looks like add-listing.html?id=...
var editId = new URLSearchParams(window.location.search).get("id");
var editing = null;
var oldPhotos = [];
var removedPhotos = [];

// ----- Photos (up to 5) -----
var MAX_PHOTOS = 5;
var chosenPhotos = [];
var photoInput = document.getElementById("photo-input");
var thumbRow = document.getElementById("thumb-row");
var photoError = document.getElementById("photo-error");
var saving = false;

// Starts the page: first the account type, then (when editing) the old listing
async function startPage() {
  await findAccountType();
  if (editId) {
    await loadForEdit();
  }
}
startPage();

// Fill the form with the listing being edited
async function loadForEdit() {
  var result = await db.from("listings").select("*").eq("id", editId).single();
  if (result.error || !result.data) {
    showFormError("We could not find that listing.");
    return;
  }
  editing = result.data;
  var item = editing;

  document.title = "Edit listing | CampusLodge";
  document.querySelector("h1.title").innerHTML = 'Edit your <span class="green-word">listing</span>';
  document.querySelector('#add-form button[type="submit"]').textContent =
    item.status === "live" || item.status === "taken" ? "Save changes" : "Submit for approval";
  if (item.status === "live" || item.status === "taken") {
    document.getElementById("save-draft").hidden = true;
  }

  document.getElementById("title").value = item.title;
  document.getElementById("room-type").value = item.room_type || "";
  document.getElementById("area").value = item.area || "";
  document.getElementById("price").value = item.price;
  document.getElementById("distance").value = item.distance_min || "";
  document.getElementById("description").value = item.description || "";
  document.getElementById("whatsapp").value = item.whatsapp || "";
  document.getElementById("call-number").value = item.call_number || "";

  if (item.kind === "hostel") {
    document.querySelector('input[name="hostel-gender"][value="' + item.hostel_gender + '"]').checked = true;
    document.getElementById("beds").value = item.beds || "";
  }

  document.querySelectorAll('input[name="amenity"]').forEach(function (box) {
    box.checked = (item.amenities || []).indexOf(box.parentNode.textContent.trim()) !== -1;
  });

  oldPhotos = (item.photos || []).slice();
  drawThumbs();
}

// Make a photo smaller (max 1280 px) and turn it into a JPEG.
// Phone photos are big, and this keeps the free storage safe.
function shrinkPhoto(file) {
  return new Promise(function (resolve, reject) {
    var picture = new Image();
    var url = URL.createObjectURL(file);
    picture.onload = function () {
      var scale = Math.min(1, 1280 / Math.max(picture.width, picture.height));
      var canvas = document.createElement("canvas");
      canvas.width = Math.round(picture.width * scale);
      canvas.height = Math.round(picture.height * scale);
      canvas.getContext("2d").drawImage(picture, 0, 0, canvas.width, canvas.height);
      URL.revokeObjectURL(url);
      canvas.toBlob(function (blob) {
        if (blob) {
          resolve(blob);
        } else {
          reject();
        }
      }, "image/jpeg", 0.8);
    };
    picture.onerror = reject;
    picture.src = url;
  });
}

function showPhotoMessage(text) {
  photoError.textContent = text;
  photoError.hidden = false;
}

// Make one small picture with an X to remove it
function makeThumb(source, number, onRemove) {
  var box = document.createElement("div");
  box.className = "photo-box thumb";
  box.innerHTML = '<img alt="Photo ' + number + '"><button type="button" class="thumb-remove" aria-label="Remove photo">&times;</button>';
  box.querySelector("img").src = source;
  box.querySelector("button").addEventListener("click", onRemove);
  return box;
}

// Show the old photos first, then the new ones
function drawThumbs() {
  thumbRow.innerHTML = "";
  oldPhotos.forEach(function (path, index) {
    thumbRow.appendChild(makeThumb(photoUrl(path), index + 1, function () {
      removedPhotos.push(path);
      oldPhotos.splice(index, 1);
      drawThumbs();
    }));
  });
  chosenPhotos.forEach(function (photo, index) {
    thumbRow.appendChild(makeThumb(photo.preview, oldPhotos.length + index + 1, function () {
      URL.revokeObjectURL(photo.preview);
      chosenPhotos.splice(index, 1);
      drawThumbs();
    }));
  });
}

photoInput.addEventListener("change", async function () {
  photoError.hidden = true;
  var files = Array.from(photoInput.files);
  photoInput.value = "";

  for (var i = 0; i < files.length; i++) {
    if (oldPhotos.length + chosenPhotos.length >= MAX_PHOTOS) {
      showPhotoMessage("You can add up to " + MAX_PHOTOS + " photos.");
      break;
    }
    if (["image/jpeg", "image/png", "image/webp"].indexOf(files[i].type) === -1) {
      showPhotoMessage("Use JPG, PNG or WebP photos only.");
      continue;
    }
    try {
      var blob = await shrinkPhoto(files[i]);
      chosenPhotos.push({ blob: blob, preview: URL.createObjectURL(blob) });
    } catch (error) {
      showPhotoMessage("One photo could not be read. Try another one.");
    }
  }
  drawThumbs();
});

async function saveListing(status) {
  if (saving) {
    return;
  }
  formError.hidden = true;
  photoError.hidden = true;

  var title = document.getElementById("title").value.trim();
  var price = toNumber(document.getElementById("price").value);
  var distance = toNumber(document.getElementById("distance").value);
  var kind = isHostel ? "hostel" : "apartment";

  // A live or taken listing keeps its status when edited
  // (the database sends a changed live listing back to Pending)
  if (editing && (editing.status === "live" || editing.status === "taken")) {
    status = editing.status;
  }

  // Check the two things every listing needs
  var titleBad = title.length < 3;
  var priceBad = price < 1;
  document.getElementById("title-error").hidden = !titleBad;
  document.getElementById("price-error").hidden = !priceBad;
  // A listing sent for approval needs at least one photo (a draft does not)
  var photoBad = status !== "draft" && oldPhotos.length + chosenPhotos.length === 0;
  if (photoBad) {
    showPhotoMessage("Add at least one photo.");
  }
  if (titleBad || priceBad || photoBad) {
    showFormError("Fix the highlighted parts before you continue.");
    return;
  }

  saving = true;

  // Upload the photos into this person's own folder
  var userResult = await db.auth.getUser();
  var folder = userResult.data.user.id;
  var photoPaths = [];
  for (var i = 0; i < chosenPhotos.length; i++) {
    var path = folder + "/" + Date.now() + "-" + i + "-" + Math.floor(Math.random() * 100000) + ".jpg";
    var upload = await db.storage
      .from("listing-photos")
      .upload(path, chosenPhotos[i].blob, { contentType: "image/jpeg" });
    if (upload.error) {
      await db.storage.from("listing-photos").remove(photoPaths);
      saving = false;
      showFormError("A photo could not be uploaded. Please try again.");
      return;
    }
    photoPaths.push(path);
  }

  // Hostel details only count for campus hostels
  var gender = null;
  var beds = null;
  if (kind === "hostel") {
    gender = document.querySelector('input[name="hostel-gender"]:checked').value;
    beds = toNumber(document.getElementById("beds").value);
  }

  var amenities = [];
  document.querySelectorAll('input[name="amenity"]:checked').forEach(function (box) {
    amenities.push(box.parentNode.textContent.trim());
  });

  var fields = {
    title: title,
    room_type: document.getElementById("room-type").value,
    area: document.getElementById("area").value,
    price: price,
    distance_min: distance || null,
    hostel_gender: gender,
    beds: beds,
    amenities: amenities,
    description: document.getElementById("description").value.trim() || null,
    whatsapp: document.getElementById("whatsapp").value.trim().slice(0, 20) || null,
    call_number: document.getElementById("call-number").value.trim().slice(0, 20) || null,
    photos: oldPhotos.concat(photoPaths),
    status: status
  };

  var result;
  if (editing) {
    result = await db.from("listings").update(fields).eq("id", editing.id);
  } else {
    fields.kind = kind;
    result = await db.from("listings").insert(fields);
  }

  if (result.error) {
    // Do not leave the uploaded photos behind
    await db.storage.from("listing-photos").remove(photoPaths);
    saving = false;
    showFormError("We could not save the listing. Please try again.");
    return;
  }

  // Photos the lister removed while editing are deleted for good
  if (removedPhotos.length > 0) {
    await db.storage.from("listing-photos").remove(removedPhotos);
  }
  window.location.href = "lister.html";
}

addForm.addEventListener("submit", function (event) {
  event.preventDefault();
  saveListing("pending");
});

document.getElementById("save-draft").addEventListener("click", function () {
  saveListing("draft");
});
