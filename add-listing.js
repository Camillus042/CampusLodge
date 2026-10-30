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

// ----- Photos (up to 5) -----
var MAX_PHOTOS = 5;
var chosenPhotos = [];
var photoInput = document.getElementById("photo-input");
var thumbRow = document.getElementById("thumb-row");
var photoError = document.getElementById("photo-error");
var saving = false;

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

// Show the small pictures with an X to remove each one
function drawThumbs() {
  thumbRow.innerHTML = "";
  chosenPhotos.forEach(function (photo, index) {
    var box = document.createElement("div");
    box.className = "photo-box thumb";
    box.innerHTML = '<img alt="Photo ' + (index + 1) + '"><button type="button" class="thumb-remove" aria-label="Remove photo">&times;</button>';
    box.querySelector("img").src = photo.preview;
    box.querySelector("button").addEventListener("click", function () {
      URL.revokeObjectURL(photo.preview);
      chosenPhotos.splice(index, 1);
      drawThumbs();
    });
    thumbRow.appendChild(box);
  });
}

photoInput.addEventListener("change", async function () {
  photoError.hidden = true;
  var files = Array.from(photoInput.files);
  photoInput.value = "";

  for (var i = 0; i < files.length; i++) {
    if (chosenPhotos.length >= MAX_PHOTOS) {
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
  var kind = document.querySelector('input[name="listing-type"]:checked').value;

  // Check the two things every listing needs
  var titleBad = title.length < 3;
  var priceBad = price < 1;
  document.getElementById("title-error").hidden = !titleBad;
  document.getElementById("price-error").hidden = !priceBad;
  // A listing sent for approval needs at least one photo (a draft does not)
  var photoBad = status === "pending" && chosenPhotos.length === 0;
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

  var result = await db.from("listings").insert({
    kind: kind,
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
    photos: photoPaths,
    status: status
  });

  if (result.error) {
    // Do not leave the uploaded photos behind
    await db.storage.from("listing-photos").remove(photoPaths);
    saving = false;
    showFormError("We could not save the listing. Please try again.");
    return;
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
