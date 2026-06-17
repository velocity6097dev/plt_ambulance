let pharmacyData = {
    items: [],
    cash: 0,
    hasInsurance: false,
    insuranceCost: 5000,
    activeTab: 'general',
    prescriptions: [],
    currentPrescription: null,
    isEMS: false,
    cart: []
};

window.addEventListener('message', function(event) {
    let item = event.data;
    switch(item.action) {
        case 'amb_openPharmacy':
            openPharmacy(item.data);
            break;
        case 'amb_updatePharmacyCash':
            updatePharmacyCash(item.cash);
            break;
        case 'amb_setPrescriptionWriter':
            openPrescriptionWriter(item.patientName, item.targetSrc);
            break;
        case 'amb_updateInsuranceStatus':
            updateInsuranceStatus(item.hasInsurance);
            break;
        case 'amb_viewPrescription':
            viewPrescription(item.data);
            break;
        case 'amb_refreshPharmacyData':
            if (item.data && item.data.hasInsurance != null) {
                updateInsuranceStatus(item.data.hasInsurance);
            }
            if (item.data && item.data.insuranceCost != null) {
                pharmacyData.insuranceCost = item.data.insuranceCost;
                $('#ph-ins-cost').text('$' + Number(item.data.insuranceCost).toLocaleString());
            }
            if (item.data && item.data.insuranceDiscount != null) {
                pharmacyData.insuranceDiscount = item.data.insuranceDiscount;
            }
            pharmacyData.prescriptions = (item.data && item.data.prescriptions) || [];
            pharmacyData.cash = (item.data && item.data.cash) != null ? item.data.cash : pharmacyData.cash;
            if (item.data && item.data.cash != null) $('#ph-cash-val').text('$' + item.data.cash.toLocaleString());
            if (pharmacyData.activeTab === 'prescription') renderPrescriptionItems();
            break;
    }
});

function openPharmacy(data) {
    pharmacyData.items = data.items;
    pharmacyData.cash = data.cash;
    pharmacyData.hasInsurance = data.hasInsurance;
    pharmacyData.insuranceCost = data.insuranceCost;
    pharmacyData.insuranceDiscount = data.insuranceDiscount || 0.5;
    pharmacyData.isEMS = data.isEMS;
    pharmacyData.prescriptions = data.prescriptions || [];
    pharmacyData.currentPrescription = null;
    pharmacyData.linkedJob = data.linkedJob;
    pharmacyData.cart = []; // Reset cart on open
    
    $('#ph-cash-val').text('$' + pharmacyData.cash.toLocaleString());
    $('#ph-ins-cost').text('$' + pharmacyData.insuranceCost.toLocaleString());
    
    updateInsuranceStatus(pharmacyData.hasInsurance);
    renderCart(); // Initial cart render
    
    if (pharmacyData.isEMS) {
        $('.professional-tab').removeClass('hidden');
    } else {
        $('.professional-tab').addClass('hidden');
    }
    
    switchTab('general');
    $('#pharmacy-container').removeClass('hidden').fadeIn(400).css('display', 'flex');
}

function updatePharmacyCash(cash) {
    pharmacyData.cash = cash;
    $('#ph-cash-val').text('$' + cash.toLocaleString());
}

function updateInsuranceStatus(hasInsurance) {
    pharmacyData.hasInsurance = hasInsurance;
    const buyBtn = $('#ph-buy-insurance');

    if (hasInsurance) {
        buyBtn
            .text('INSURED')
            .prop('disabled', true)
            .addClass('is-insured')
            .attr('title', 'You already own PLUTO HEALTH+');
    } else {
        buyBtn
            .text(window.ambT('ui_activate', 'ACTIVATE'))
            .prop('disabled', false)
            .removeClass('is-insured')
            .removeAttr('title');
    }
    
    if ($('#pharmacy-container').is(':visible')) {
        renderItems();
        renderCart(); // Refresh prices in cart
    }
}

function switchTab(tab) {
    pharmacyData.activeTab = tab;
    
    $('.ph-nav-item').removeClass('active');
    $(`.ph-nav-item[data-tab="${tab}"]`).addClass('active');
    
    $('.ph-view').removeClass('active');
    
    if (tab === 'general' || tab === 'professional') {
        $('#ph-items-view').addClass('active');
        renderItems();
    } else if (tab === 'prescription') {
        $('#ph-prescription-view').addClass('active');
        renderPrescriptionItems();
    } else if (tab === 'insurance') {
        $('#ph-insurance-view').addClass('active');
    }
}

function renderItems() {
    let grid = $('#ph-items-grid');
    grid.empty();
    
    pharmacyData.items.forEach((item, index) => {
        if (pharmacyData.activeTab === 'general' && (item.professionalOnly || item.prescriptionRequired)) return;
        if (pharmacyData.activeTab === 'professional' && !item.professionalOnly) {
            // Only allow prescription items in professional tab if user is EMS and it's prescriptionRequired
            if (!(pharmacyData.isEMS && item.prescriptionRequired)) return;
        }
        
        let price = item.price;
        if (pharmacyData.hasInsurance && !item.professionalOnly) {
            price = Math.floor(price * (1 - (pharmacyData.insuranceDiscount || 0.5)));
        }
        
        let icon = item.icon || (item.name + ".png");
        
        let card = $(`
            <div class="ph-item-card" style="animation: itemAppear 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards ${index * 0.05}s">
                <div class="ph-card-header">
                    <h3>${item.label}</h3>
                    <div class="ph-item-meta">
                        <span class="ph-item-stock">x50</span>
                        <div class="ph-item-info-icon"><i class="fas fa-info"></i></div>
                    </div>
                </div>
                <div class="ph-item-image-wrap">
                    <img src="nui://${GetParentResourceName()}/web/img/${icon}" onerror="this.src='nui://${GetParentResourceName()}/web/img/fallback.webp'">
                </div>
                <div class="ph-card-footer">
                    <button class="ph-add-to-cart-btn" data-name="${item.name}">${window.ambT('ui_add_to_cart', 'Add to Cart')}</button>
                    <div class="ph-item-price-tag">$${price.toLocaleString()}</div>
                </div>
            </div>
        `);
        
        card.find('.ph-add-to-cart-btn').on('click', function() {
            addToCart(item, price);
        });
        
        grid.append(card);
    });
}

function renderPrescriptionItems() {
    const grid = $('#ph-prescription-grid');
    const empty = $('#ph-prescription-empty');
    grid.empty();

    const itemToPrescs = {};
    (pharmacyData.prescriptions || []).forEach(p => {
        const key = String(p.item || '').toLowerCase().trim();
        if (!key) return;
        if (!itemToPrescs[key]) itemToPrescs[key] = [];
        itemToPrescs[key].push(p);
    });

    let shown = 0;
    pharmacyData.items.forEach((item, index) => {
        const prescs = itemToPrescs[String(item.name).toLowerCase().trim()] || [];
        if (prescs.length === 0) return;

        shown++;
        let unitPrice = item.price;
        if (pharmacyData.hasInsurance) unitPrice = Math.floor(unitPrice * (1 - (pharmacyData.insuranceDiscount || 0.5)));

        let icon = item.icon || (item.name + ".png");

        const card = $(`
            <div class="ph-item-card" style="animation: itemAppear 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards ${index * 0.05}s">
                <div class="ph-card-header">
                    <h3>${item.label}</h3>
                    <div class="ph-item-meta">
                        <span class="ph-item-stock">x${prescs.length}</span>
                        <div class="ph-item-info-icon"><i class="fas fa-info"></i></div>
                    </div>
                </div>
                <div class="ph-item-image-wrap">
                    <img src="nui://${GetParentResourceName()}/web/img/${icon}" onerror="this.src='nui://${GetParentResourceName()}/web/img/fallback.webp'">
                </div>
                <div class="ph-card-footer">
                    <button class="ph-add-to-cart-btn presc-btn" data-name="${item.name}">${window.ambT('ui_claim_presc', 'Claim Presc')}</button>
                    <div class="ph-item-price-tag">$${unitPrice.toLocaleString()}</div>
                </div>
            </div>
        `);

        card.find('.ph-add-to-cart-btn').on('click', function() {
            addToCart(item, unitPrice, prescs); // Pass full prescs array to pick unused slot
        });

        grid.append(card);
    });

    if (shown === 0) empty.removeClass('hidden');
    else empty.addClass('hidden');
}

/* CART LOGIC */
function getUsedPrescriptionSlots(itemName) {
    return pharmacyData.cart
        .filter(i => i.name === itemName && i.prescriptionSlots)
        .flatMap(i => i.prescriptionSlots);
}

function addToCart(item, price, prescsArray) {
    const isPrescription = prescsArray && Array.isArray(prescsArray) && prescsArray.length > 0;
    
    if (isPrescription) {
        const usedSlots = getUsedPrescriptionSlots(item.name);
        const unusedPresc = prescsArray.find(p => p.slot != null && !usedSlots.includes(p.slot));
        if (!unusedPresc) return; // No more prescriptions available
        
        const existing = pharmacyData.cart.find(i => i.name === item.name && i.prescriptionSlots);
        if (existing) {
            existing.prescriptionSlots.push(unusedPresc.slot);
            existing.quantity++;
        } else {
            pharmacyData.cart.push({
                name: item.name,
            label: item.label,
            price: price,
            quantity: 1,
            icon: item.icon,
            prescriptionSlots: [unusedPresc.slot]
        });
    }
} else {
    const existing = pharmacyData.cart.find(i => i.name === item.name && !i.prescriptionSlots);
    if (existing) {
        existing.quantity++;
    } else {
        pharmacyData.cart.push({
            name: item.name,
            label: item.label,
            price: price,
            quantity: 1,
            icon: item.icon,
            prescriptionSlots: null
        });
    }
}
    renderCart();
}

function removeFromCart(index) {
    pharmacyData.cart.splice(index, 1);
    renderCart();
}

function updateCartQty(index, delta) {
    const cartItem = pharmacyData.cart[index];
    
    if (delta > 0 && cartItem.prescriptionSlots) {
        const itemKey = String(cartItem.name).toLowerCase().trim();
        const availablePrescs = (pharmacyData.prescriptions || []).filter(p => String(p.item || '').toLowerCase().trim() === itemKey);
        const usedSlots = getUsedPrescriptionSlots(cartItem.name);
        if (usedSlots.length >= availablePrescs.length) return;
        const unusedPresc = availablePrescs.find(p => p.slot != null && !usedSlots.includes(p.slot));
        if (!unusedPresc) return;
        cartItem.prescriptionSlots.push(unusedPresc.slot);
    }
    
    cartItem.quantity += delta;
    if (cartItem.quantity <= 0) {
        pharmacyData.cart.splice(index, 1);
    } else if (delta < 0 && cartItem.prescriptionSlots) {
        cartItem.prescriptionSlots.pop();
    }
    renderCart();
}

function renderCart() {
    const list = $('#ph-cart-list');
    list.empty();
    
    let total = 0;
    
    pharmacyData.cart.forEach((item, index) => {
        total += item.price * item.quantity;
        
        let icon = item.icon || (item.name + ".png");
        
        const cartItem = $(`
            <div class="ph-cart-item">
                <div class="ph-cart-icon-wrap">
                    <img src="nui://${GetParentResourceName()}/web/img/${icon}" onerror="this.src='nui://${GetParentResourceName()}/web/img/fallback.webp'">
                </div>
                <div class="ph-cart-info">
                    <h4>${item.label}</h4>
                    <div class="ph-cart-qty-ctrl">
                        <button onclick="updateCartQty(${index}, -1)">-</button>
                        <span>${item.quantity}</span>
                        <button onclick="updateCartQty(${index}, 1)">+</button>
                    </div>
                </div>
                <div class="ph-cart-price-group">
                    <div class="ph-cart-item-price">$${(item.price * item.quantity).toLocaleString()}</div>
                    <button class="ph-cart-remove-btn" onclick="removeFromCart(${index})"><i class="fas fa-times"></i></button>
                </div>
            </div>
        `);
        list.append(cartItem);
    });
    
    $('#ph-cart-total-val').text('$' + total.toLocaleString());
}

function checkout(paymentType) {
    if (pharmacyData.cart.length === 0) return;
    
    let total = 0;
    pharmacyData.cart.forEach(i => total += i.price * i.quantity);
    
    if (pharmacyData.cash < total && paymentType === 'cash') {
        // We still send it, the server will check bank vs cash usually, 
        // but here the server script only checks player cash.
        // If we want a proper bank vs cash checkout, we'd need server changes.
        // For now, I'll follow the existing buyItem pattern.
    }

    // Process each item in cart
    pharmacyData.cart.forEach(item => {
        const payload = {
            item: item.name,
            price: item.price,
            quantity: item.quantity,
            linkedJob: pharmacyData.linkedJob,
            paymentType: paymentType // Note: current server script doesn't use this yet
        };
        
        if (item.prescriptionSlots && item.prescriptionSlots.length) {
            payload.prescriptionSlots = item.prescriptionSlots;
        }
        
        $.post(`https://${GetParentResourceName()}/pharmacyBuyItem`, JSON.stringify(payload));
    });
    
    pharmacyData.cart = [];
    renderCart();
    closePharmacy();
}

function closePharmacy() {
    $('#pharmacy-container').fadeOut(400, function() {
        $(this).addClass('hidden');
        $.post(`https://${GetParentResourceName()}/closePharmacy`, JSON.stringify({}));
    });
}

$(document).on('click', '.ph-nav-item', function() {
    switchTab($(this).data('tab'));
});

function sendBuyInsuranceRequest() {
    if (pharmacyData.hasInsurance) return;
    $.post(`https://${GetParentResourceName()}/buyInsurance`, JSON.stringify({
        linkedJob: pharmacyData.linkedJob
    }));
}

$(document).off('click', '#ph-buy-insurance').on('click', '#ph-buy-insurance', function() {
    sendBuyInsuranceRequest();
});

$(document).on('keydown', function(event) {
    if (event.key === "Escape") {
        if ($('#prescription-viewer-container').is(':visible')) {
            $('#prescription-viewer-container').fadeOut(300).addClass('hidden');
            $.post(`https://${GetParentResourceName()}/closePrescriptionViewer`, JSON.stringify({}));
        }
        else if ($('#pharmacy-container').is(':visible')) closePharmacy();
        else if ($('#prescription-writer-container').is(':visible')) {
            $('#prescription-writer-container').fadeOut(300).addClass('hidden');
        }
    }
});

/* PRESCRIPTION VIEWER (FOR PLAYER) */
function viewPrescription(data) {
    $('#view-presc-patient').text(data.patientName);
    $('#view-presc-date').text(data.issuedAt);
    $('#view-presc-item').text(data.itemLabel);
    $('#view-presc-qty').text(data.quantity);
    $('#view-presc-notes').text(data.notes);
    $('#view-presc-signature').text(data.doctorName);
    $('#view-presc-dept').text((data.doctorDept || "Medical").toUpperCase());
    
    $('#prescription-viewer-container').removeClass('hidden').fadeIn(400).css('display', 'flex');
}

/* PRESCRIPTION WRITER (FOR EMS) */
let currentPrescTarget = null;
function openPrescriptionWriter(patientName, targetSrc) {
    currentPrescTarget = targetSrc;
    $('#presc-target-name').val(patientName);
    $('#presc-notes').val('');
    $('#prescription-writer-container').removeClass('hidden').fadeIn(300).css('display', 'flex');
}

$('#sign-prescription-btn').on('click', function() {
    let data = {
        targetSrc: currentPrescTarget,
        item: $('#presc-item-select').val(),
        itemLabel: $('#presc-item-select option:selected').text(),
        quantity: parseInt($('#presc-quantity').val()),
        notes: $('#presc-notes').val(),
        duration: parseInt($('#presc-duration').val())
    };
    $.post(`https://${GetParentResourceName()}/issuePrescription`, JSON.stringify(data));
    $('#prescription-writer-container').fadeOut(300).addClass('hidden');
});

$('#presc-item-select').on('change', function() {
    if ($(this).val() === 'iak_wheelchair') {
        $('#presc-duration-field').removeClass('hidden');
    } else {
        $('#presc-duration-field').addClass('hidden');
    }
});

window.closePrescriptionWriter = function() {
    $('#prescription-writer-container').fadeOut(300).addClass('hidden');
};
