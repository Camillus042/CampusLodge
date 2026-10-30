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

async function saveListing(status) {
  formError.hidden = true;

  var title = document.getElementById("title").value.trim();
  var price = toNumber(document.getElementById("price").value);
  var distance = toNumber(document.getElementById("distance").value);
  var kind = document.querySelector('input[name="listing-type"]:checked').value;

  // Check the two things every listing needs
  var titleBad = title.length < 3;
  var priceBad = price < 1;
  document.getElementById("title-error").hidden = !titleBad;
  document.getElementById("price-error").hidden = !priceBad;
  if (titleBad || priceBad) {
    showFormError("Fix the highlighted parts before you continue.");
    return;
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
    status: status
  });

  if (result.error) {
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
