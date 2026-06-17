let currentEMSInventory = {};
let activeCategory = 'first_kit';

window.openEMSInventory = function(data) {
    const container = document.getElementById('ems-inventory-container');
    if (!container) return;
    
    container.classList.remove('hidden');
    container.style.display = 'flex';
    
    currentEMSInventory = data.items || {};
    renderEMSInventory();
};

window.closeEMSInventory = function() {
    const container = document.getElementById('ems-inventory-container');
    if (container) {
        container.classList.add('hidden');
        container.style.display = 'none';
    }
    fetch(`https://${GetParentResourceName()}/amb_close`, {
        method: 'POST'
    });
};

function renderEMSInventory() {
    const list = document.getElementById('ems-inventory-list');
    if (!list) return;

    list.innerHTML = '';
    
    const categories = [
        { id: 'first_kit', label: 'FIRST KIT' },
        { id: 'operations', label: 'OPERATIONS' },
        { id: 'equipments', label: 'EQUIPMENTS' }
    ];

    categories.forEach(cat => {
        const items = currentEMSInventory[cat.id] || [];
        if (items.length > 0) {
            const catHeader = document.createElement('div');
            catHeader.className = 'ems-inv-category-header';
            catHeader.innerText = cat.label;
            list.appendChild(catHeader);

            const grid = document.createElement('div');
            grid.className = 'ems-inventory-grid';

            items.forEach(item => {
                const div = document.createElement('div');
                div.className = 'ems-inv-item-card';
                div.innerHTML = `
                    <div class="ems-inv-item-icon">
                        <img src="nui://${GetParentResourceName()}/web/img/${item.name}.png" onerror="this.src='nui://${GetParentResourceName()}/web/img/default.png'" alt="${item.label}">
                    </div>
                    <div class="ems-inv-item-info">
                        <div class="ems-inv-item-label">${item.label}</div>
                        <div class="ems-inv-item-weight">${(item.weight / 1000).toFixed(1)}kg</div>
                    </div>
                    <button class="ems-inv-take-btn" onclick="takeEMSItem('${item.name}')">TAKE</button>
                `;
                grid.appendChild(div);
            });
            list.appendChild(grid);
        }
    });
}

window.takeEMSItem = function(itemName) {
    fetch(`https://${GetParentResourceName()}/amb_takeEMSItem`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ item: itemName })
    });
};

// NUI Listener for Inventory
window.addEventListener('message', (event) => {
    if (event.data.action === 'amb_openInventory') {
        window.openEMSInventory(event.data);
    }
});

