let currentBagId = null;
let currentBagNetId = null;
let itemImagePath = "img/";

window.addEventListener('message', function(event) {
    if (event.data.action === 'amb_openBagUI') {
        openBagInventory(event.data);
    }
});

function openBagInventory(data) {
    console.log("Opening Bag UI with data:", data);
    currentBagId = data.bagId;
    currentBagNetId = data.netId;
    itemImagePath = data.imagePath || "img/";
    
    $('#bag-inventory-container').removeClass('hidden').css('display', 'flex').hide().fadeIn(300);
    
    // Render Bag Section
    renderSlots('#bag-slots-container', data.items, data.maxSlots, 'takeBagItem', 'bag');
    updateWeight('#bag-weight-fill', '#bag-weight-text', data.weight, data.maxWeight);
    
    // Render Player Section
    if (data.playerItems) {
        console.log("Rendering player items:", data.playerItems.length);
        renderSlots('#player-slots-container', data.playerItems, data.playerMaxSlots, 'storeInBag', 'player');
        updateWeight('#player-weight-fill', '#player-weight-text', data.playerWeight, data.playerMaxWeight);
    } else {
        console.error("No player items received in data!");
    }
}

function renderSlots(containerSelector, items, maxSlots, clickFuncName, type) {
    const container = $(containerSelector);
    container.empty();
    
    for (let i = 1; i <= maxSlots; i++) {
        const item = items.find(it => it.slot === i);
        let slotHtml = '';
        
        if (item) {
            slotHtml = `
                <div class="bag-slot occupied ${type}-slot" onclick="${clickFuncName}(${i})">
                    <div class="slot-number">${i}</div>
                    <img src="${itemImagePath}${item.name}.png" class="slot-icon" onerror="this.src='img/default.png'">
                    <div class="slot-amount">${item.count}</div>
                    <div class="item-tooltip">${item.label}</div>
                </div>
            `;
        } else {
            slotHtml = `
                <div class="bag-slot empty">
                    <div class="slot-number">${i}</div>
                </div>
            `;
        }
        container.append(slotHtml);
    }
}

function updateWeight(fillSelector, textSelector, current, max) {
    const percent = Math.min((current / max) * 100, 100);
    $(fillSelector).css('width', percent + '%');
    $(textSelector).text(`${(current / 1000).toFixed(1)}kg / ${(max / 1000).toFixed(1)}kg`);
}

function closeBagInventory() {
    $('#bag-inventory-container').fadeOut(300, function() {
        $(this).addClass('hidden');
    });
    $.post(`https://${GetParentResourceName()}/amb_closeBag`, JSON.stringify({
        netId: currentBagNetId
    }));
    currentBagId = null;
    currentBagNetId = null;
}

function takeBagItem(slot) {
    const qty = parseInt($('#transfer-quantity').val()) || 0;
    $.post(`https://${GetParentResourceName()}/amb_takeBagItem`, JSON.stringify({
        bagId: currentBagId,
        netId: currentBagNetId,
        slot: slot,
        amount: qty
    }));
}

function storeInBag(slot) {
    const qty = parseInt($('#transfer-quantity').val()) || 0;
    $.post(`https://${GetParentResourceName()}/amb_storeInBag`, JSON.stringify({
        bagId: currentBagId,
        netId: currentBagNetId,
        slot: slot,
        amount: qty
    }));
}

// Global close helper
$(document).keyup(function(e) {
    if (e.key === "Escape") {
        if ($('#bag-inventory-container').is(':visible')) {
            closeBagInventory();
        }
    }
});
