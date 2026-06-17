// 2025 iMac Boss Menu - Modern Experience

// Global scope initialization
window.highestZIndex = 50;
window.currentDeptData = null;
window.currentJobName = null;
window.currentPlayerName = "OFFICER";
window.currentPlayerRank = "SERGEANT";
window.financeHistory = {};
window.syncedWarrants = [];
window.syncedCaseFiles = [];
window.syncedBolos = [];
window.syncedDeptNews = [];
window.syncedDutyLogs = {};

// Function: Render Department Members Content
window.renderDepartmentMembers = function(tabOrShowLoader, showLoaderParam) {
    let tab = 'personnel';
    let showLoader = true;
    if (typeof tabOrShowLoader === 'string') {
        tab = tabOrShowLoader;
        showLoader = showLoaderParam !== false;
    } else if (typeof tabOrShowLoader === 'boolean') {
        showLoader = tabOrShowLoader;
    }

    const content = document.getElementById(`mac-app-container-dept`);
    if (!content) return;

    if (showLoader) content.innerHTML = `<div class="mac-loader"></div>`;
    
    let deptLabel = "Department";
    if (window.currentDeptData && window.currentDeptData.nodes) {
        const node = window.currentDeptData.nodes.find(n => n.id === window.currentJobName);
        if (node) deptLabel = node.label;
    }

    if (tab === 'hire') {
        const rankNode = window.currentDeptData && window.currentDeptData.links && window.currentDeptData.nodes
            ? (() => {
                const rankLinks = window.currentDeptData.links.filter(l => l.from === window.currentJobName || l.to === window.currentJobName);
                for (const link of rankLinks) {
                    const targetId = link.from === window.currentJobName ? link.to : link.from;
                    const found = window.currentDeptData.nodes.find(n => n.id === targetId && n.type === 'rank');
                    if (found) return found;
                }
                return null;
            })()
            : null;
        const grades = (rankNode && rankNode.ranks) ? rankNode.ranks : [{ level: 0, name: 'Trainee' }];
        const gradeOptions = grades.map(g => `<option value="${g.level}">${g.name || 'Level ' + g.level}</option>`).join('');
        
        content.innerHTML = `
            <div class="mac-app-container-glass">
                <div class="mac-app-header">
                    <div class="mac-app-header-top">
                        <div class="mac-app-icon-large" style="background: none; box-shadow: none;">
                            <img src="img/departments.png" style="width: 100%; height: 100%; object-fit: contain;">
                        </div>
                        <div class="mac-app-titles">
                            <h2>${deptLabel}</h2>
                            <p>HIRE BY CITIZEN ID</p>
                        </div>
                    </div>
                    <div class="mac-app-tabs">
                        <button class="mac-tab-btn" onclick="window.renderDepartmentMembers('personnel')">Personnel</button>
                        <button class="mac-tab-btn active" onclick="window.renderDepartmentMembers('hire')">Hire by ID</button>
                    </div>
                </div>
                <div class="mac-scroll-area" style="padding: 25px;">
                    <div class="inline-form-card" style="max-width: 400px;">
                        <div class="form-header"><span>HIRE NEW MEMBER</span></div>
                        <div class="intranet-input-group">
                            <label>Citizen ID</label>
                            <input type="text" id="hire-citizen-id" placeholder="e.g. ABC12345 or Server ID (1-999)">
                        </div>
                        <div class="intranet-input-group">
                            <label>Starting Rank</label>
                            <select id="hire-grade" style="width: 100%; padding: 10px 12px; border: 1px solid #ddd; border-radius: 6px; font-size: 13px;">
                                ${gradeOptions}
                            </select>
                        </div>
                        <div class="form-footer">
                            <button class="mac-btn-primary slim" onclick="window.submitHireById()">
                                <i class="fas fa-user-plus"></i> Hire
                            </button>
                        </div>
                    </div>
                    <p style="font-size: 12px; color: #8E8E93; margin-top: 15px;">Enter the Citizen ID (e.g. ABC12345) to hire an offline player, or their Server ID (the # number when online) to hire someone currently in the server.</p>
                </div>
            </div>
        `;
        return;
    }

    fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(res => res.json())
    .then(players => {
        // Show ALL players as requested by the user
        const deptMembers = players;
        
        const list = deptMembers.map(p => {
            // Ensure medals and divisions are arrays
            const medals = Array.isArray(p.medals) ? p.medals : (typeof p.medals === 'object' ? Object.values(p.medals) : []);
            const memberDivs = Array.isArray(p.divisions) ? p.divisions : (typeof p.divisions === 'object' ? Object.values(p.divisions) : []);
            
            const medalIcons = medals.slice(0, 5).map(m => {
                if (!m || !m.id) return '';
                return `
                    <div class="member-medal-mini" title="${m.name || 'Honored'}">
                        <img src="img/${m.id}.webp" onerror="this.src='img/members.png';">
                    </div>
                `;
            }).join('');

            const divLabels = (window.currentDeptData.divisions && window.currentDeptData.divisions[window.currentJobName]) 
                ? window.currentDeptData.divisions[window.currentJobName]
                    .filter(d => memberDivs.includes(d.id))
                    .map(d => `<span class="member-div-badge">${d.name}</span>`)
                    .join('')
                : '';

            return `
            <div class="mac-member-card ${!p.isOnline ? 'is-offline' : ''}">
                <div class="mac-member-info-left">
                    <div class="member-avatar-ios">
                        ${p.name.charAt(0)}
                        <div class="online-indicator ${p.isOnline ? 'online' : 'offline'}"></div>
                    </div>
                    <div class="member-details-ios">
                        <div class="member-name-ios">
                            ${p.name} 
                            <span class="ios-id-tag">${p.isOnline ? '#' + p.id : 'OFFLINE'}</span>
                        </div>
                        <div class="member-rank-ios">${p.jobGradeLabel}</div>
                        <div class="member-medals-row">
                            ${medalIcons || '<span class="no-medals">No Honors Awarded</span>'}
                        </div>
                        <div class="member-divisions-row">${divLabels}</div>
                    </div>
                </div>
                <div class="mac-member-actions-slim">
                    <button class="ios-slim-btn" onclick="window.manageMember('${p.cid}', 'promote')">
                        <i class="fas fa-chevron-up"></i>
                        <span>Promote</span>
                    </button>
                    <button class="ios-slim-btn" onclick="window.manageMember('${p.cid}', 'demote')">
                        <i class="fas fa-chevron-down"></i>
                        <span>Demote</span>
                    </button>
                    <button class="ios-slim-btn danger" onclick="window.manageMember('${p.cid}', 'fire')">
                        <i class="fas fa-user-slash"></i>
                        <span>Fire</span>
                    </button>
                </div>
            </div>
        `}).join('');
        
        content.innerHTML = `
            <div class="mac-app-container-glass">
                <div class="mac-app-header">
                    <div class="mac-app-header-top">
                        <div class="mac-app-icon-large" style="background: none; box-shadow: none;">
                            <img src="img/departments.png" style="width: 100%; height: 100%; object-fit: contain;">
                        </div>
                        <div class="mac-app-titles">
                            <h2>${deptLabel}</h2>
                            <p>${deptMembers.length} ACTIVE PERSONNEL</p>
                        </div>
                    </div>
                    <div class="mac-app-tabs">
                        <button class="mac-tab-btn active" onclick="window.renderDepartmentMembers('personnel')">Personnel</button>
                        <button class="mac-tab-btn" onclick="window.renderDepartmentMembers('hire')">Hire by ID</button>
                    </div>
                </div>
                <div class="mac-scroll-area">${list || '<div class="mac-empty-state">No personnel found.</div>'}</div>
            </div>
        `;
    });
}

window.submitHireById = function() {
    const idInput = document.getElementById('hire-citizen-id');
    const gradeSelect = document.getElementById('hire-grade');
    if (!idInput || !gradeSelect) return;
    
    const idVal = (idInput.value || '').trim();
    if (!idVal) return;
    
    const grade = parseInt(gradeSelect.value, 10) || 0;
    
    fetch(`https://${GetParentResourceName()}/amb_hireById`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            id: idVal,
            job: window.currentJobName,
            grade: grade
        })
    })
    .then(r => r.json())
    .then(result => {
        if (result && result.success) {
            idInput.value = '';
            window.renderDepartmentMembers('personnel', false);
        } else {
            if (typeof window.showNotification === 'function') {
                window.showNotification('Hire Failed', null, result && result.message ? result.message : 'Check the ID and try again.');
            }
        }
    })
    .catch(() => {
        if (typeof window.showNotification === 'function') {
            window.showNotification('Hire Failed', null, 'Check the ID and try again.');
        }
    });
};

// Function: Open App (Modern macOS Style)
window.openMacApp = function(type) {
    if (type === 'mdt') {
        window.openMacApp('safari');
        setTimeout(() => window.renderSafariApp('patients'), 550);
        return;
    }

    let windowId = 'members';
    let appName = 'Records';
    if (type === 'dept_manager') { windowId = 'dept'; appName = 'Departments'; }
    else if (type === 'finances') { windowId = 'finances'; appName = 'Finances'; }
    else if (type === 'safari') { windowId = 'safari'; appName = 'Safari'; }
    else if (type === 'calculator') { windowId = 'calculator'; appName = 'Calculator'; }
    else if (type === 'clock') { windowId = 'clock'; appName = 'Clock'; }
    else if (type === 'mail') { windowId = 'mail'; appName = 'Mail'; }
    else if (type === 'settings') { windowId = 'settings'; appName = 'Settings'; }
    else if (type === 'member_db') { windowId = 'members'; appName = 'Records'; }
    
    const win = document.getElementById(`mac-window-${windowId}`);
    
    if (!win) return;
    
    // Add active dot to dock item
    let dockId = 'dock-members';
    if (type === 'dept_manager') dockId = 'dock-dept';
    else if (type === 'finances') dockId = 'dock-finances';
    else if (type === 'safari') dockId = 'dock-safari';
    else if (type === 'calculator') dockId = 'dock-calculator';
    else if (type === 'clock') dockId = 'dock-clock';
    else if (type === 'mail') dockId = 'dock-mail';
    else if (type === 'settings') dockId = 'dock-settings';
    else if (type === 'member_db') dockId = 'dock-members';
    
    const dockItem = document.getElementById(dockId);
    if (dockItem) {
        dockItem.classList.add('app-open');
        dockItem.classList.add('bouncing');
        setTimeout(() => {
            dockItem.classList.remove('bouncing');
        }, 800); // Match animation duration
    }
    
    // Update active app name in top bar
    const activeAppName = document.getElementById('active-app-name');
    if (activeAppName) activeAppName.innerText = appName;
    
    setTimeout(() => {
        win.classList.remove('hidden');
        win.style.display = 'flex';
        win.style.zIndex = ++window.highestZIndex;
        
        if (type === 'dept_manager') {
            window.renderDepartmentMembers(true);
        } else if (type === 'finances') {
            window.renderFinancesApp('main');
        } else if (type === 'member_db') {
            window.renderMembersApp('main');
        } else if (type === 'safari') {
            window.renderSafariApp('intranet');
        } else if (type === 'clock') {
            window.renderClockApp();
        } else if (type === 'mail') {
            window.renderMailApp();
        } else if (type === 'settings') {
            window.renderSettingsApp();
        } else if (type === 'calculator') {
            if (window.renderCalculatorApp) window.renderCalculatorApp();
        }
    }, 500);
};

// Function: Render Safari Browser Content
window.renderSafariApp = function(page, subPage = 'news') {
    const windowId = 'safari';
    const content = document.getElementById(`mac-app-container-${windowId}`);
    const tabContainer = document.getElementById('safari-tabs');
    const urlText = document.getElementById('safari-url-text');
    if (!content || !tabContainer) return;

    // Update URL bar
    if (urlText) {
        urlText.innerText = `dept.pear.os/${page}/${subPage}`;
    }

    // Render Tabs
    const tabs = [
        { id: 'intranet', label: 'Medical Portal', icon: 'globe' },
        { id: 'logs', label: 'Duty Logs', icon: 'list-check' },
        { id: 'insurance', label: 'Insurance', icon: 'shield-halved' },
        { id: 'patients', label: 'Patient DB', icon: 'address-book' }
    ];

    tabContainer.innerHTML = tabs.map(t => `
        <div class="safari-tab ${page === t.id ? 'active' : ''}" onclick="window.renderSafariApp('${t.id}')">
            <i class="fas fa-${t.icon}"></i>
            <span>${t.label}</span>
            <i class="fas fa-times tab-close"></i>
        </div>
    `).join('');

    let innerHTML = '';

    if (page === 'intranet') {
        // Portal Navigation
        const navItems = [
            { id: 'news', label: 'Department News', icon: 'newspaper' },
            { id: 'pcrs', label: 'Incident Reports (PCR)', icon: 'file-medical' },
            { id: 'dmr', label: 'Medical Records (DMR)', icon: 'address-book' }
        ];

        const sidebarNav = navItems.map(item => `
            <div class="nav-item ${subPage === item.id ? 'active' : ''}" onclick="window.renderSafariApp('intranet', '${item.id}')">
                <i class="fas fa-${item.icon}"></i>
                <span>${item.label}</span>
            </div>
        `).join('');

        let subContent = '';

        if (subPage === 'news') {
            const newsList = (window.syncedDeptNews || []).slice().reverse().map(n => `
                <div class="news-article">
                    <div class="article-meta">${n.date.toUpperCase()} • ${n.author.toUpperCase()}</div>
                    <h2>${n.title.toUpperCase()}</h2>
                    <p>${n.content}</p>
                    <div class="article-actions">
                        <button class="action-icon-btn danger" onclick="window.deleteNews(${n.id})" title="DELETE ARTICLE">
                            <i class="fas fa-trash"></i>
                        </button>
                    </div>
                </div>
            `).join('') || `
                <div class="news-article">
                    <div class="article-meta">FEBRUARY 7, 2026 • COMMAND STAFF</div>
                    <h2>WELCOME TO THE MEDICAL PORTAL</h2>
                    <p>All personnel are required to review the new Department News updated this morning. Safety first.</p>
                </div>
            `;

            subContent = `
                <div class="warrants-header">
                    <div class="header-titles-warrant">
                        <h2>Department News</h2>
                        <p>Official bulletins and announcements</p>
                    </div>
                    <button class="intranet-btn-new" id="btn-toggle-news-form" onclick="window.toggleNewsForm()">
                        <i class="fas fa-plus"></i> NEW ARTICLE
                    </button>
                </div>

                <div id="inline-news-form" class="inline-form-card" style="display: none;">
                    <div class="form-header"><span>CREATE NEW DEPARTMENT ANNOUNCEMENT</span></div>
                    <div class="intranet-input-group">
                        <label>Article Title</label>
                        <input type="text" id="news-title" placeholder="e.g. New Equipment Training">
                    </div>
                    <div class="intranet-input-group">
                        <label>Content</label>
                        <textarea id="news-content" placeholder="Enter details..." style="height: 120px;"></textarea>
                    </div>
                    <div class="form-footer">
                        <button class="intranet-btn-sm" onclick="window.toggleNewsForm()">Cancel</button>
                        <button class="intranet-btn-sm primary" onclick="window.submitNewsInline()">Post to Portal</button>
                    </div>
                </div>

                <div class="content-block">
                    <div class="block-header">LATEST BULLETINS</div>
                    <div class="block-body news-full-list">${newsList}</div>
                </div>
            `;
        } else if (subPage === 'pcrs') {
            const pcrList = (window.syncedPCRs || []).slice().reverse().map(p => `
                <div class="news-article">
                    <div class="article-meta">${p.date.toUpperCase()} • ${p.author.toUpperCase()}</div>
                    <h2>PATIENT: ${p.patient.toUpperCase()}</h2>
                    <div style="margin-bottom: 10px;">
                        <span class="badge warning" style="margin-right: 10px;">CONDITION: ${p.condition.toUpperCase()}</span>
                    </div>
                    <p><strong>Treatment:</strong> ${p.treatment}</p>
                </div>
            `).join('') || '<div class="intra-empty">No Patient Care Reports filed yet.</div>';

            subContent = `
                <div class="warrants-header">
                    <div class="header-titles-warrant">
                        <h2>Patient Care Reports</h2>
                        <p>Documented medical interactions and field treatments</p>
                    </div>
                    <button class="intranet-btn-new" id="btn-toggle-pcr-form" onclick="window.togglePCRForm()">
                        <i class="fas fa-file-medical"></i> FILE NEW REPORT
                    </button>
                </div>

                <div id="inline-pcr-form" class="inline-form-card" style="display: none;">
                    <div class="form-header"><span>NEW INCIDENT LOG (PCR)</span></div>
                    <div class="form-grid">
                        <div class="intranet-input-group">
                            <label>Patient Name</label>
                            <input type="text" id="pcr-patient" placeholder="e.g. John Doe">
                        </div>
                        <div class="intranet-input-group">
                            <label>Condition / Incident</label>
                            <input type="text" id="pcr-condition" placeholder="e.g. GSW to Left Leg">
                        </div>
                    </div>
                    <div class="intranet-input-group">
                        <label>Treatment Given</label>
                        <textarea id="pcr-treatment" placeholder="Describe medical actions taken..." style="height: 100px;"></textarea>
                    </div>
                    <div class="form-footer">
                        <button class="intranet-btn-sm" onclick="window.togglePCRForm()">Cancel</button>
                        <button class="intranet-btn-sm primary" onclick="window.submitPCRInline()">Submit Report</button>
                    </div>
                </div>

                <div class="content-block">
                    <div class="block-header">RECENT INCIDENT LOGS</div>
                    <div class="block-body news-full-list">${pcrList}</div>
                </div>
            `;
        } else if (subPage === 'dmr') {
            subContent = `
                <div class="warrants-header">
                    <div class="header-titles-warrant">
                        <h2>Digital Medical Records</h2>
                        <p>Searchable database of citizen medical history</p>
                    </div>
                </div>

                <div class="content-block" style="margin-bottom: 20px;">
                    <div class="block-body">
                        <div class="nav-search" style="width: 100%; max-width: none; background: #f8f9fa; border: 1px solid #ddd;">
                            <i class="fas fa-search" style="color: #a30000;"></i>
                            <input type="text" id="dmr-search-input" placeholder="Search by name or Citizen ID..." onkeyup="window.searchDMR()" style="color: #a30000;">
                        </div>
                    </div>
                </div>

                <div id="dmr-results-container">
                    <div class="intra-empty">Enter a name or CID to begin searching records.</div>
                </div>
            `;
        }

        innerHTML = `
            <div class="portal-container">
                <div class="portal-sidebar">
                    <div class="sidebar-header" style="color: #a30000; border-bottom: 1px solid #ffebeb;">MEDICAL PORTAL</div>
                    <div class="sidebar-nav">${sidebarNav}</div>
                </div>
                <div class="portal-content">${subContent}</div>
            </div>
        `;
    } else if (page === 'logs') {
        const logs = (window.syncedDutyLogs && window.syncedDutyLogs[window.currentJobName]) || [];
        const activeLogs = logs.slice().reverse(); // Newest first

        const logList = activeLogs.map(l => `
            <tr>
                <td>${l.officer}</td>
                <td><span class="ios-status-tag ${l.action === 'Clocked On' ? 'success' : 'error'}">${l.action.toUpperCase()}</span></td>
                <td>${l.date} ${l.time}</td>
            </tr>
        `).join('');

        innerHTML = `
            <div class="safari-page-container">
                <div class="safari-standard-header">
                    <h1>Duty Logs</h1>
                    <p>Real-time record of officer activity.</p>
                </div>
                <table class="safari-table">
                    <thead>
                        <tr><th>Officer</th><th>Action</th><th>Timestamp</th></tr>
                    </thead>
                    <tbody>
                        ${logList || '<tr><td colspan="3" style="text-align:center; padding: 20px;">No logs recorded yet.</td></tr>'}
                    </tbody>
                </table>
            </div>
        `;
    } else if (page === 'insurance') {
        innerHTML = `
            <div class="safari-page-container">
                <div class="safari-standard-header">
                    <h1><i class="fas fa-shield-halved" style="color:#a30000; margin-right:8px;"></i>Insurance Subscribers</h1>
                    <p>Active medical coverage plans registered with the department.</p>
                </div>
                <div id="insurance-loading" style="text-align:center; padding: 40px; color:#666;">
                    <i class="fas fa-spinner fa-spin" style="font-size:24px; margin-bottom:12px; display:block;"></i>
                    Loading subscriber list...
                </div>
                <table class="safari-table" id="insurance-table" style="display:none;">
                    <thead>
                        <tr><th>CITIZEN ID</th><th>FULL NAME</th><th>STATUS</th><th>ACTION</th></tr>
                    </thead>
                    <tbody id="insurance-tbody"></tbody>
                </table>
            </div>
        `;
    } else if (page === 'patients') {
        innerHTML = window.getMDTAppHTML();
    }

    content.innerHTML = `
        <div class="safari-browser-view">
            <div class="safari-content-area">${innerHTML}</div>
        </div>
    `;

    // Fetch insurance subscribers if on that tab
    if (page === 'insurance') {
        fetch(`https://${GetParentResourceName()}/amb_getInsuredPlayers`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ jobName: window.currentJobName })
        })
        .then(r => r.json())
        .then(list => {
            const loading = document.getElementById('insurance-loading');
            const table = document.getElementById('insurance-table');
            const tbody = document.getElementById('insurance-tbody');
            if (!tbody) return;
            if (loading) loading.style.display = 'none';
            if (table) table.style.display = '';

            if (!list || list.length === 0) {
                tbody.innerHTML = `<tr><td colspan="4" style="text-align:center; padding:24px; color:#888;">No active insurance subscribers found.</td></tr>`;
                return;
            }

            tbody.innerHTML = list.map(p => `
                <tr>
                    <td><span style="font-family:monospace; font-size:11px; color:#888;">${p.cid}</span></td>
                    <td><strong>${p.name}</strong></td>
                    <td><span class="ios-status-tag ${p.isOnline ? 'success' : ''}">${p.isOnline ? '● ONLINE' : '○ OFFLINE'}</span></td>
                    <td>
                        <button class="intranet-btn-danger" onclick="window.cancelInsurance('${p.cid}', ${p.serverId || 'null'}, '${(p.name || "").replace(/'/g, "\\'")}')">
                            <i class="fas fa-ban"></i> CANCEL
                        </button>
                    </td>
                </tr>
            `).join('');
        });
    }
};
        // Insurance cancel action
window.cancelInsurance = function(cid, serverId, name) {
    fetch(`https://${GetParentResourceName()}/amb_cancelInsurance`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cid: cid, serverId: serverId })
    });
    // Refresh the list after a short delay
    setTimeout(() => window.renderSafariApp('insurance'), 800);
};

// Global Clock Update (for Dock Icon and Clock App)
window.updateSystemClock = function() {
    const now = new Date();
    const seconds = now.getSeconds();
    const minutes = now.getMinutes();
    const hours = now.getHours();

    const secDeg = (seconds / 60) * 360;
    const minDeg = ((minutes + seconds / 60) / 60) * 360;
    const hourDeg = (((hours % 12) + minutes / 60) / 12) * 360;

    // Analog Hands (App)
    const hHand = document.getElementById('clock-hour');
    const mHand = document.getElementById('clock-minute');
    const sHand = document.getElementById('clock-second');

    if (hHand) hHand.style.transform = `translateX(-50%) rotate(${hourDeg}deg)`;
    if (mHand) mHand.style.transform = `translateX(-50%) rotate(${minDeg}deg)`;
    if (sHand) sHand.style.transform = `translateX(-50%) rotate(${secDeg}deg)`;

    // Digital Time (App)
    const digitalTime = document.getElementById('digital-time');
    if (digitalTime) {
        digitalTime.innerText = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    }

    // Digital Date (App)
    const digitalDate = document.getElementById('digital-date');
    if (digitalDate) {
        digitalDate.innerText = now.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
    }

    // Update Dock Icon Clock
    const dockH = document.querySelector('#dock-clock .clock-hand-dock.hour');
    const dockM = document.querySelector('#dock-clock .clock-hand-dock.minute');
    const dockS = document.querySelector('#dock-clock .clock-hand-dock.second');

    if (dockH) dockH.style.transform = `translateX(-50%) rotate(${hourDeg}deg)`;
    if (dockM) dockM.style.transform = `translateX(-50%) rotate(${minDeg}deg)`;
    if (dockS) dockS.style.transform = `translateX(-50%) rotate(${secDeg}deg)`;

    requestAnimationFrame(window.updateSystemClock);
};

// Start clock immediately
window.updateSystemClock();

// Function: Render Clock App
window.renderClockApp = function() {
    const content = document.getElementById('mac-app-container-clock');
    if (!content) return;

    content.innerHTML = `
        <div class="clock-app-container">
            <div class="analog-clock">
                <div class="clock-center"></div>
                <div class="clock-hand hour" id="clock-hour"></div>
                <div class="clock-hand minute" id="clock-minute"></div>
                <div class="clock-hand second" id="clock-second"></div>
            </div>
            <div class="digital-time" id="digital-time">...</div>
            <div class="digital-date" id="digital-date">...</div>
        </div>
    `;
};

// Function: Render Settings App
window.renderSettingsApp = function(section = 'general') {
    const content = document.getElementById('mac-app-container-settings');
    if (!content) return;

    let sectionContent = '';
    if (section === 'general') {
        sectionContent = `
            <h2 class="settings-section-title">General</h2>
            <div class="settings-group">
                <div class="settings-row">
                    <span class="settings-row-label">Computer Name</span>
                    <span class="settings-row-value">${window.currentJobName ? window.currentJobName.toUpperCase() : 'DEPT-PC-01'}</span>
                </div>
                <div class="settings-row">
                    <span class="settings-row-label">OS Version</span>
                    <span class="settings-row-value">PearOS Sequoia 15.2</span>
                </div>
            </div>
            <div class="settings-group">
                <div class="settings-row">
                    <span class="settings-row-label">Automatic Updates</span>
                    <div class="settings-toggle active"><div class="settings-toggle-dot"></div></div>
                </div>
            </div>
        `;
    } else if (section === 'display') {
        sectionContent = `
            <h2 class="settings-section-title">Display</h2>
            <div class="settings-group">
                <div class="settings-row">
                    <span class="settings-row-label">Brightness</span>
                    <input type="range" style="width: 150px;">
                </div>
                <div class="settings-row">
                    <span class="settings-row-label">Night Shift</span>
                    <div class="settings-toggle"><div class="settings-toggle-dot"></div></div>
                </div>
            </div>
            <div class="settings-group">
                <div class="settings-row">
                    <span class="settings-row-label">True Tone</span>
                    <div class="settings-toggle active"><div class="settings-toggle-dot"></div></div>
                </div>
            </div>
        `;
    } else if (section === 'appearance') {
        sectionContent = `
            <h2 class="settings-section-title">Appearance</h2>
            <div class="settings-group">
                <div class="settings-row">
                    <span class="settings-row-label">Dark Mode</span>
                    <div class="settings-toggle active"><div class="settings-toggle-dot"></div></div>
                </div>
                <div class="settings-row">
                    <span class="settings-row-label">Accent Color</span>
                    <div style="display: flex; gap: 8px;">
                        <div style="width: 16px; height: 16px; border-radius: 50%; background: #007aff; border: 2px solid #fff; box-shadow: 0 0 0 1px #007aff;"></div>
                        <div style="width: 16px; height: 16px; border-radius: 50%; background: #ff3b30;"></div>
                        <div style="width: 16px; height: 16px; border-radius: 50%; background: #34c759;"></div>
                    </div>
                </div>
            </div>
        `;
    }

    content.innerHTML = `
        <div class="settings-app">
            <div class="settings-sidebar">
                <div class="settings-nav-item ${section === 'general' ? 'active' : ''}" onclick="window.renderSettingsApp('general')">
                    <i class="fas fa-cog"></i> General
                </div>
                <div class="settings-nav-item ${section === 'appearance' ? 'active' : ''}" onclick="window.renderSettingsApp('appearance')">
                    <i class="fas fa-palette"></i> Appearance
                </div>
                <div class="settings-nav-item ${section === 'display' ? 'active' : ''}" onclick="window.renderSettingsApp('display')">
                    <i class="fas fa-desktop"></i> Display
                </div>
                <div class="settings-nav-item ${section === 'accessibility' ? 'active' : ''}" onclick="window.renderSettingsApp('accessibility')">
                    <i class="fas fa-universal-access"></i> Accessibility
                </div>
                <div class="settings-nav-item ${section === 'wallpaper' ? 'active' : ''}" onclick="window.renderSettingsApp('wallpaper')">
                    <i class="fas fa-image"></i> Wallpaper
                </div>
            </div>
            <div class="settings-content-area">
                ${sectionContent}
            </div>
        </div>
    `;
};

// Function: Render Finances App with Tab Support
window.renderFinancesApp = function(tab, showLoader = true) {
    const windowId = 'finances';
    const content = document.getElementById(`mac-app-container-${windowId}`);
    if (!content) return;

    if (showLoader) content.innerHTML = `<div class="mac-loader"></div>`;

    // Ensure we have a job name
    if (!window.currentJobName || window.currentJobName === 'none') {
        content.innerHTML = `<div class="mac-empty-state">No department job detected. Please ensure you are logged in.</div>`;
        return;
    }

    fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(res => res.json())
    .then(players => {
        if (!players) throw new Error('No players data received');
        
        const deptMembers = players.filter(p => {
            if (p.cid && p.cid.startsWith('FAKE_')) return true;
            return p.jobName === window.currentJobName;
        });
        
        // Find Rank Data for current department (Search all links)
        let rankNode = null;
        if (window.currentDeptData && window.currentDeptData.links && window.currentDeptData.nodes) {
            const rankLinks = window.currentDeptData.links.filter(l => l.from === window.currentJobName || l.to === window.currentJobName);
            for (const link of rankLinks) {
                const targetId = link.from === window.currentJobName ? link.to : link.from;
                const found = window.currentDeptData.nodes.find(n => n.id === targetId && n.type === 'rank');
                if (found) {
                    rankNode = found;
                    break;
                }
            }
        }

        let totalWeeklySalary = 0;
        deptMembers.forEach(member => {
            if (rankNode && rankNode.ranks) {
                const rank = rankNode.ranks.find(r => r.level == member.jobGradeLevel);
                if (rank) totalWeeklySalary += (rank.pay || 0);
            }
        });

        const budget = (window.deptBalances && window.deptBalances[window.currentJobName]) || 250000; 
        const avgSalary = deptMembers.length > 0 ? Math.round(totalWeeklySalary / deptMembers.length) : 0;

        const deptHistory = window.financeHistory[window.currentJobName] || [];
        let chartData = deptHistory.map(entry => entry.balance);
        
        if (chartData.length < 7) {
            const paddingCount = 7 - chartData.length;
            const firstVal = chartData.length > 0 ? chartData[0] : budget;
            const padding = Array(paddingCount).fill(firstVal);
            chartData = [...padding, ...chartData];
        } else if (chartData.length > 7) {
            chartData = chartData.slice(-7);
        }

        chartData[chartData.length - 1] = budget; // Chart shows budget history

        const maxVal = Math.max(...chartData, budget) * 1.1;
        const minVal = Math.min(...chartData) * 0.9;
        const range = maxVal - minVal || 1; 
        
        const chartPoints = chartData.map((val, i) => ({
            x: (i / (chartData.length - 1)) * 100,
            y: 100 - ((val - minVal) / range) * 100
        }));

        function getBezierPath(points) {
            if (points.length < 2) return "";
            let path = `M ${points[0].x},${points[0].y}`;
            for (let i = 0; i < points.length - 1; i++) {
                const p0 = points[i];
                const p1 = points[i + 1];
                const cp1x = p0.x + (p1.x - p0.x) / 2;
                path += ` C ${cp1x},${p0.y} ${cp1x},${p1.y} ${p1.x},${p1.y}`;
            }
            return path;
        }

        const smoothedPath = getBezierPath(chartPoints);

        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        let labels = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            labels.push(days[d.getDay()]);
        }

        let innerContent = '';
        if (tab === 'main') {
            innerContent = `
                <div class="mac-finance-summary-row">
                    <div class="finance-card">
                        <div class="finance-card-label">Net Balance</div>
                        <div class="finance-card-value">$${budget.toLocaleString()}</div>
                    </div>
                    <div class="finance-card">
                        <div class="finance-card-label">Expenses</div>
                        <div class="finance-card-value danger">-$${totalWeeklySalary.toLocaleString()}</div>
                    </div>
                    <div class="finance-card">
                        <div class="finance-card-label">Average Salary</div>
                        <div class="finance-card-value success">$${avgSalary.toLocaleString()}</div>
                    </div>
                </div>

                <div class="mac-finance-actions-row">
                    <div class="finance-input-group">
                        <span class="currency-prefix">$</span>
                        <input type="number" id="finance-amount" placeholder="0" min="1">
                    </div>
                    <button class="mac-finance-btn deposit" onclick="window.financeAction('deposit')">
                        <i class="fas fa-arrow-up"></i>
                        <span>Deposit</span>
                    </button>
                    <button class="mac-finance-btn withdraw" onclick="window.financeAction('withdraw')">
                        <i class="fas fa-arrow-down"></i>
                        <span>Withdraw</span>
                    </button>
                </div>

                <div class="mac-finance-chart-container">
                    <div class="chart-header">
                        <h3>Balance History</h3>
                        <span class="chart-period">Last 7 Days</span>
                    </div>
                    <div class="chart-wrapper">
                        <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="finance-svg-chart">
                            <defs>
                                <linearGradient id="chartGradient" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="0%" stop-color="rgba(52, 199, 89, 0.3)" />
                                    <stop offset="100%" stop-color="rgba(52, 199, 89, 0)" />
                                </linearGradient>
                            </defs>
                            <path d="${smoothedPath} L 100,100 L 0,100 Z" fill="url(#chartGradient)" />
                            <path d="${smoothedPath}" fill="none" stroke="#34C759" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round" />
                        </svg>
                        <div class="chart-labels-x">
                            ${labels.map(l => `<span>${l}</span>`).join('')}
                        </div>
                    </div>
                </div>

                <div class="mac-finance-stats">
                    <div class="stat-row">
                        <span>Total Staff</span>
                        <span>${deptMembers.length}</span>
                    </div>
                </div>
            `;
        } else if (tab === 'salary') {
            let salaryList = '<div class="mac-empty-state">No ranks configured.</div>';
            if (rankNode && rankNode.ranks) {
                salaryList = rankNode.ranks.map(r => `
                    <div class="salary-row editable">
                        <div class="salary-rank-info">
                            <span class="rank-level-tag">Lvl ${r.level}</span>
                            <span class="rank-name">${r.name}</span>
                        </div>
                        <div class="salary-input-wrapper">
                            <span>$</span>
                            <input type="number" value="${r.pay || 0}" 
                                onchange="window.updateRankSalary('${rankNode.id}', ${r.level}, this.value)">
                        </div>
                    </div>
                `).join('');
            }
            innerContent = `
                <div class="mac-salary-list">
                    ${salaryList}
                </div>
            `;
        }

        let currentAutoPay = 'none';
        if (window.deptAutoPay && window.currentJobName) {
            currentAutoPay = window.deptAutoPay[window.currentJobName] || 'none';
        }

        content.innerHTML = `
            <div class="mac-app-container-glass finance-app">
                <div class="mac-app-header">
                    <div class="mac-app-header-top">
                        <div class="mac-app-icon-large" style="background: none; box-shadow: none;">
                            <img src="img/finances.png" style="width: 100%; height: 100%; object-fit: contain;">
                        </div>
                        <div class="mac-app-titles">
                            <h2>Finances</h2>
                            <p>${tab === 'main' ? 'DEPARTMENT BUDGET' : 'RANK SALARIES'}</p>
                        </div>
                    </div>
                    <div class="mac-app-tabs">
                        <button class="mac-tab-btn ${tab === 'main' ? 'active' : ''}" onclick="window.renderFinancesApp('main')">Overview</button>
                        <button class="mac-tab-btn ${tab === 'salary' ? 'active' : ''}" onclick="window.renderFinancesApp('salary')">Salary</button>
                    </div>
                </div>
                <div class="mac-scroll-area finance-content">
                    ${innerContent}
                </div>
                ${tab === 'salary' ? `
                    <div class="mac-app-footer ios-style-footer">
                        <button class="ios-btn primary" onclick="window.distributeSalaries()">
                            Pay Once
                        </button>
                        <div class="ios-btn-group">
                            <button class="ios-btn-item ${currentAutoPay === 'hourly' ? 'active' : ''}" onclick="window.toggleAutoPay('hourly')">Hourly</button>
                            <button class="ios-btn-item ${currentAutoPay === 'daily' ? 'active' : ''}" onclick="window.toggleAutoPay('daily')">Daily</button>
                        </div>
                        <button class="ios-btn danger ${currentAutoPay === 'none' ? 'hidden' : ''}" onclick="window.toggleAutoPay('none')">
                            Cancel
                        </button>
                    </div>
                ` : ''}
            </div>
        `;
    })
    .catch(err => {
        console.error('Finances App Error:', err);
        content.innerHTML = `<div class="mac-empty-state">Error loading financial data. Please try again.</div>`;
    });
};

window.distributeSalaries = function() {
    fetch(`https://${GetParentResourceName()}/distributeSalaries`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            dept: window.currentJobName
        })
    }).then(() => {
        // UI will be updated via syncData if needed
    });
};

window.financeAction = function(action) {
    const amountInput = document.getElementById('finance-amount');
    if (!amountInput) return;
    
    const amount = amountInput.value;
    if (amount === null || amount === "") return;
    const num = parseInt(amount);
    if (isNaN(num) || num <= 0) return;

    fetch(`https://${GetParentResourceName()}/financeAction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            dept: window.currentJobName,
            action: action,
            amount: num
        })
    }).then(() => {
        amountInput.value = '';
    });
};

// Function: Member Management Handlers
window.manageMember = function(citizenid, action) {
    fetch(`https://${GetParentResourceName()}/amb_manageMember`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            cid: citizenid,
            action: action,
            dept: window.currentJobName
        })
    }).then(() => {
        // Refresh the app content after action
        window.openMacApp('dept_manager');
    });
};

window.updateRankSalary = function(rankNodeId, level, newValue) {
    const salary = parseInt(newValue);
    if (isNaN(salary)) return;

    fetch(`https://${GetParentResourceName()}/updateRankSalary`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            rankNodeId: rankNodeId,
            level: level,
            pay: salary
        })
    });
};

window.toggleAutoPay = function(type) {
    if (!window.currentJobName) return;
    
    // Optimistic UI update
    if (!window.deptAutoPay) window.deptAutoPay = {};
    window.deptAutoPay[window.currentJobName] = type;
    
    // Refresh without loader for smooth transition
    window.renderFinancesApp('salary', false);

    fetch(`https://${GetParentResourceName()}/toggleAutoPay`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            dept: window.currentJobName,
            type: type
        })
    });
};

// Function: Close App (Global)
window.closeMacApp = function(windowId) {
    const win = document.getElementById(`mac-window-${windowId}`);
    if (win) {
        // Remove active dot from dock
        let dockId = 'dock-members';
        if (windowId === 'dept') dockId = 'dock-dept';
        else if (windowId === 'finances') dockId = 'dock-finances';
        else if (windowId === 'safari') dockId = 'dock-safari';
        else if (windowId === 'calculator') dockId = 'dock-calculator';
        else if (windowId === 'clock') dockId = 'dock-clock';
        else if (windowId === 'mail') dockId = 'dock-mail';
        else if (windowId === 'settings') dockId = 'dock-settings';
        
        const dockItem = document.getElementById(dockId);
        if (dockItem) dockItem.classList.remove('app-open');

        win.style.animation = 'scaleOut 0.2s ease-in forwards';
        setTimeout(() => {
            win.style.display = 'none';
            win.classList.add('hidden');
            win.style.animation = ''; // Reset animation
            
            // Revert top bar title if no windows left
            const visibleWindows = document.querySelectorAll('.mac-window:not(.hidden)');
            const activeAppName = document.getElementById('active-app-name');
            if (activeAppName) {
                if (visibleWindows.length === 0) {
                    activeAppName.innerText = 'Desktop';
                } else {
                    // Find the one with highest z-index
                    let topWin = null;
                    let maxZ = -1;
                    visibleWindows.forEach(w => {
                        const z = parseInt(w.style.zIndex || 0);
                        if (z > maxZ) { maxZ = z; topWin = w; }
                    });
                    if (topWin) {
                        const activeAppName = document.getElementById('active-app-name');
                        const appName = topWin.getAttribute('data-app');
                        if (activeAppName && appName) {
                            activeAppName.innerText = appName;
                        }
                    }
                }
            }
        }, 200);
    }
};

// Function: Shutdown PC (Modern Style)
window.shutdownPC = function() {
    const container = document.getElementById('boss-menu-container');
    const chassis = document.querySelector('.macintosh-chassis');
    
    if (chassis) {
        chassis.style.transition = 'opacity 0.5s ease-out, transform 0.5s ease-out';
        chassis.style.opacity = '0';
        chassis.style.transform = 'scale(0.95)';
    }
    
    // Close all windows on shutdown
    window.closeMacApp('dept');
    window.closeMacApp('members');
    window.closeMacApp('finances');
    window.closeMacApp('safari');
    window.closeMacApp('calculator');
    window.closeMacApp('clock');
    window.closeMacApp('mail');
    window.closeMacApp('settings');
    
    // Clear all dock dots
    document.querySelectorAll('.dock-item').forEach(item => {
        item.classList.remove('app-open');
    });
    
    const activeAppName = document.getElementById('active-app-name');
    if (activeAppName) activeAppName.innerText = 'Desktop';
    
    setTimeout(() => {
        if (container) {
            container.classList.remove('visible');
            container.style.display = 'none';
        }
        if (chassis) {
            chassis.style.opacity = '1';
            chassis.style.transform = 'scale(1)';
        }
        fetch(`https://${GetParentResourceName()}/amb_close`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    }, 500);
};

// Modern Power On sequence
window.startMacBoot = function() {
    const container = document.getElementById('boss-menu-container');
    const boot = document.getElementById('boot-screen');
    const desktop = document.querySelector('.macos-desktop');
    const progress = document.querySelector('.progress-fill');
    
    if (!container) return;

    container.style.display = 'flex';
    container.classList.add('visible');
    
    // Instant Boot Sequence
    if (boot) boot.style.display = 'none'; // Skip boot screen for instant experience
    if (desktop) {
        desktop.style.display = 'flex';
        desktop.style.opacity = '1';
        desktop.style.transition = 'none';
    }
};

// NUI Message Listener
window.addEventListener('message', (event) => {
    if (event.data.action === 'amb_openBossMenu') {
        window.currentDeptData = event.data.data;
        window.externalDepts = event.data.externalDepts || [];
        window.currentJobName = event.data.jobName;
        window.currentPlayerName = event.data.playerName || "MEDICAL";
        window.currentPlayerRank = event.data.playerRank || "DOCTOR";
        window.financeHistory = event.data.finances || {};
        window.deptBalances = event.data.balances || {};
        window.deptAutoPay = event.data.autoPay || {};
        window.syncedTransactions = event.data.transactions || {};
        window.syncedMembers = event.data.members || {};
        window.syncedDeptNews = event.data.news || [];
        window.syncedDutyLogs = event.data.dutyLogs || {};
        window.startMacBoot();
    } else if (event.data.action === 'amb_syncData') {
        if (event.data.data) window.currentDeptData = event.data.data;
        if (event.data.finances) window.financeHistory = event.data.finances;
        if (event.data.balances) window.deptBalances = event.data.balances;
        if (event.data.autoPay) window.deptAutoPay = event.data.autoPay;
        if (event.data.transactions) {
            window.syncedTransactions = event.data.transactions;
        } else if (window.currentJobName && window.financeHistory && window.financeHistory[window.currentJobName]) {
            window.syncedTransactions = window.financeHistory[window.currentJobName];
        }
        if (event.data.members) window.syncedMembers = event.data.members;
        if (event.data.news) window.syncedDeptNews = event.data.news;
        if (event.data.dutyLogs) window.syncedDutyLogs = event.data.dutyLogs;

        // Refresh Finances app if open
        const financesWin = document.getElementById('mac-window-finances');
        if (financesWin && !financesWin.classList.contains('hidden')) {
            const activeTab = financesWin.querySelector('.mac-tab-btn.active');
            if (activeTab) {
                const tabType = activeTab.innerText === 'Overview' ? 'main' : 'salary';
                window.renderFinancesApp(tabType, false);
            }
        }

        // Refresh Members app if open
        const membersWin = document.getElementById('mac-window-members');
        if (membersWin && !membersWin.classList.contains('hidden')) {
            const activeTab = membersWin.querySelector('.mac-tab-btn.active');
            if (activeTab) {
                const tabType = activeTab.innerText === 'Database' ? 'main' : 'divisions';
                window.renderMembersApp(tabType, false);
            }
        }

        // Refresh Department app if open
        const deptWin = document.getElementById('mac-window-dept');
        if (deptWin && !deptWin.classList.contains('hidden')) {
            window.renderDepartmentMembers(false);
        }

        // Refresh Safari app if open
        const safariWin = document.getElementById('mac-window-safari');
        if (safariWin && !safariWin.classList.contains('hidden')) {
            const activeTab = safariWin.querySelector('.safari-tab.active');
            if (activeTab) {
                // Determine which page/subpage to render
                const tabLabel = activeTab.querySelector('span').innerText.toLowerCase();
                if (tabLabel === 'medical portal') {
                    const activeLink = safariWin.querySelector('.nav-links a.active');
                    const subPage = activeLink ? activeLink.innerText.trim().toLowerCase().replace(' ', '') : 'dashboard';
                    let finalSubPage = subPage;
                    if (subPage === 'casefiles') finalSubPage = 'cases';
                    else if (subPage === 'deptnews') finalSubPage = 'deptnews';
                    window.renderSafariApp('intranet', finalSubPage);
                } else if (tabLabel === 'duty logs') {
                    window.renderSafariApp('logs');
                } else if (tabLabel === 'insurance') {
                    window.renderSafariApp('insurance');
                } else if (tabLabel === 'patient db') {
                    window.renderSafariApp('patients');
                } else if (tabLabel.includes('fines')) {
                    window.renderSafariApp('fines');
                }
            }
        }
    } else if (event.data.action === 'amb_client:SyncMail') {
        const mailWin = document.getElementById('mac-window-mail');
        if (mailWin && !mailWin.classList.contains('hidden')) {
            window.renderMailApp(window.currentMailView || 'inbox', false);
        }
    } else if (event.data.action === 'syncTransactions') {
        window.syncedTransactions = event.data.transactions || {};
        const safariWin = document.getElementById('mac-window-safari');
        if (safariWin && !safariWin.classList.contains('hidden')) {
            const activeTab = safariWin.querySelector('.safari-tab.active');
            if (activeTab) {
                const tabLabel = activeTab.querySelector('span').innerText.toLowerCase();
                if (tabLabel.includes('fines')) {
                    window.renderSafariApp('fines');
                }
            }
        }
    } else if (event.data.action === 'syncMembers') {
        window.syncedMembers = event.data.members || {};
        // Refresh Members app if open
        const membersWin = document.getElementById('mac-window-members');
        if (membersWin && !membersWin.classList.contains('hidden')) {
            const activeTab = membersWin.querySelector('.mac-tab-btn.active');
            if (activeTab) {
                const tabType = activeTab.innerText === 'Database' ? 'main' : 'divisions';
                window.renderMembersApp(tabType, false);
            }
        }
        // Refresh Department app if open
        const deptWin = document.getElementById('mac-window-dept');
        if (deptWin && !deptWin.classList.contains('hidden')) {
            window.renderDepartmentMembers(false);
        }
    } else if (event.data.action === 'syncNews') {
        window.syncedDeptNews = event.data.news || [];
        // Refresh Safari app if open
        const safariWin = document.getElementById('mac-window-safari');
        if (safariWin && !safariWin.classList.contains('hidden')) {
            const activeTab = safariWin.querySelector('.safari-tab.active');
            if (activeTab) {
                const tabLabel = activeTab.querySelector('span').innerText.toLowerCase();
                if (tabLabel === 'medical portal') {
                    window.renderSafariApp('intranet', 'deptnews');
                }
            }
        }
    }
});

window.renderMembersApp = function(tab, showLoader = true) {
    const windowId = 'members';
    const content = document.getElementById(`mac-app-container-${windowId}`);
    if (!content) return;

    if (showLoader) content.innerHTML = `<div class="mac-loader"></div>`;
    
    fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(res => res.json())
    .then(players => {
        let innerContent = '';
        
        if (tab === 'main') {
            const list = players.map(p => {
                // Check if already a member of THIS department
                const isMember = p.jobName === window.currentJobName;
                
                // Get member rating
                const memberData = (window.syncedMembers && window.syncedMembers[p.cid]) || {};
                const ratings = memberData.ratings || [];
                let avgRating = 0;
                if (ratings.length > 0) {
                    const sum = ratings.reduce((acc, r) => acc + (r.overall || 0), 0);
                    avgRating = (sum / ratings.length).toFixed(1);
                }

                return `
                <div class="mac-member-card ${!p.isOnline ? 'is-offline' : ''} ${!isMember ? 'not-member' : ''}">
                    <div class="mac-member-info-left">
                        <div class="member-avatar-ios" style="background: ${isMember ? '#d32f2f' : '#5856d6'}; color: white;">
                            ${p.name.charAt(0)}
                            <div class="online-indicator ${p.isOnline ? 'online' : 'offline'}"></div>
                </div>
                        <div class="member-details-ios">
                            <div class="member-name-ios">
                                ${p.name} 
                                <span class="ios-id-tag">${p.isOnline ? '#' + p.id : 'OFFLINE'}</span>
                                ${!isMember ? '<span class="not-member-tag">NOT IN DEPT</span>' : ''}
                            </div>
                            <div class="member-rank-ios">${p.jobLabel} - ${p.jobGradeLabel}</div>
                            ${isMember ? `
                            <div class="member-rating-ios">
                                <i class="fas fa-star" style="color: ${avgRating > 0 ? '#ffcc00' : '#ccc'}"></i>
                                <span>${avgRating > 0 ? avgRating : 'No Rating'}</span>
                                <span class="rating-count">(${ratings.length} reports)</span>
                            </div>
                            ` : ''}
                        </div>
                    </div>
                    <div class="mac-member-actions-slim">
                        ${isMember ? `
                        <button class="ios-slim-btn" onclick="window.showReportModal('${p.cid}', '${p.name}')">
                            <i class="fas fa-file-signature"></i>
                            <span>Reports</span>
                        </button>
                        ` : `
                            <button class="ios-slim-btn primary" onclick="window.quickHire('${p.id}', '${p.name}')">
                                <i class="fas fa-user-plus"></i>
                                <span>Hire</span>
                            </button>
                        `}
                    </div>
                </div>
            `}).join('');
            innerContent = `<div class="mac-scroll-area">${list || '<div class="mac-empty-state">No personnel detected.</div>'}</div>`;
        } else if (tab === 'divisions') {
            const divisions = (window.currentDeptData.divisions && window.currentDeptData.divisions[window.currentJobName]) || [];
            const divList = divisions.map(d => `
                <div class="mac-division-item">
                    <div class="div-info">
                        <div class="div-icon"><i class="fas fa-layer-group"></i></div>
                        <div class="div-details">
                            <span class="div-name">${d.name}</span>
                            <span class="div-id">${d.id}</span>
                        </div>
                    </div>
                    <button class="ios-slim-btn danger compact" onclick="window.manageDivision('delete', '${d.id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            `).join('');

            innerContent = `
                <div class="mac-divisions-container">
                    <div class="mac-division-creator">
                        <input type="text" id="new-div-name" placeholder="New Division Name (e.g. K9 Unit)">
                        <button class="mac-btn-primary slim" onclick="window.manageDivision('create')">Create</button>
                    </div>
                    <div class="mac-scroll-area divisions-list">
                        ${divList || '<div class="mac-empty-state">No divisions created for this department.</div>'}
                    </div>
            </div>
        `;
        }
        
        content.innerHTML = `
            <div class="mac-app-container-glass">
                <div class="mac-app-header">
                    <div class="mac-app-header-top">
                        <div class="mac-app-icon-large" style="background: none; box-shadow: none;">
                            <img src="img/members.png" style="width: 100%; height: 100%; object-fit: contain;">
                        </div>
                        <div class="mac-app-titles">
                            <h2>Personnel Records</h2>
                            <p>${tab === 'main' ? players.length + ' TOTAL PERSONNEL' : 'DIVISION MANAGEMENT'}</p>
                        </div>
                    </div>
                    <div class="mac-app-tabs">
                        <button class="mac-tab-btn ${tab === 'main' ? 'active' : ''}" onclick="window.renderMembersApp('main')">Database</button>
                        <button class="mac-tab-btn ${tab === 'divisions' ? 'active' : ''}" onclick="window.renderMembersApp('divisions')">Divisions</button>
                    </div>
                </div>
                ${innerContent}
            </div>
        `;
    });
};

// Function: Render Apple Mail App
window.currentMailView = 'inbox';
window.currentMails = [];
window.selectedMailId = null;

window.renderMailApp = function(view = 'inbox', showLoader = true) {
    const content = document.getElementById('mac-app-container-mail');
    if (!content) return;

    window.currentMailView = view;
    if (showLoader) content.innerHTML = `<div class="mac-loader"></div>`;

    fetch(`https://${GetParentResourceName()}/amb_getMails`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dept: window.currentJobName })
    })
    .then(res => res.json())
    .then(mails => {
        window.currentMails = mails;
        
        let filteredMails = mails;
        if (view === 'inbox') {
            filteredMails = mails.filter(m => m.receiver_dept === window.currentJobName);
        } else if (view === 'sent') {
            filteredMails = mails.filter(m => m.sender_dept === window.currentJobName);
        }

        const mailListHtml = filteredMails.map(m => `
            <div class="mail-item ${m.id === window.selectedMailId ? 'active' : ''} ${!m.is_read && m.receiver_dept === window.currentJobName ? 'unread' : ''}" 
                 onclick="window.selectMail(${m.id})">
                <div class="mail-item-top">
                    <span class="mail-item-sender">${view === 'inbox' ? m.sender_name + ' (' + m.sender_dept.toUpperCase() + ')' : 'To: ' + m.receiver_dept.toUpperCase()}</span>
                    <span class="mail-item-time">${m.time}</span>
                </div>
                <div class="mail-item-subject">${m.subject || '(No Subject)'}</div>
                <div class="mail-item-preview">${m.message}</div>
            </div>
        `).join('');

        let contentPaneHtml = '<div class="mail-empty-state"><p>Select a message to read</p></div>';
        if (window.selectedMailId) {
            const mail = mails.find(m => m.id === window.selectedMailId);
            if (mail) {
                contentPaneHtml = `
                    <div class="mail-content-header">
                        <div class="mail-content-subject">${mail.subject || '(No Subject)'}</div>
                        <div class="mail-content-meta">
                            <div class="mail-sender-avatar">${mail.sender_name.charAt(0)}</div>
                            <div class="mail-meta-details">
                                <div class="mail-meta-from">From: ${mail.sender_name} (${mail.sender_dept.toUpperCase()})</div>
                                <div class="mail-meta-to">To: ${mail.receiver_dept.toUpperCase()}</div>
                            </div>
                            <div style="margin-left: auto; color: #8e8e93; font-size: 12px;">${mail.date} ${mail.time}</div>
                        </div>
                    </div>
                    <div class="mail-content-body">
                        ${mail.image_url ? `<div class="mail-image-attachment"><img src="${mail.image_url}" style="max-width: 100%; border-radius: 8px; margin-bottom: 15px; cursor: pointer; border: 1px solid #ddd;"></div>` : ''}
                        ${mail.message}
                    </div>
                `;
                
                // Mark as read if it was unread and in inbox
                if (!mail.is_read && mail.receiver_dept === window.currentJobName) {
                    fetch(`https://${GetParentResourceName()}/amb_markMailRead`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ id: mail.id })
                    });
                    mail.is_read = 1;
                }
            }
        }

        content.innerHTML = `
            <div class="mail-app-container">
                <div class="mail-sidebar">
                    <div class="mail-nav-group">
                        <div class="mail-nav-title">Mailboxes</div>
                        <div class="mail-nav-item ${view === 'inbox' ? 'active' : ''}" onclick="window.renderMailApp('inbox')">
                            <i class="fas fa-inbox"></i> Inbox
                        </div>
                        <div class="mail-nav-item ${view === 'sent' ? 'active' : ''}" onclick="window.renderMailApp('sent')">
                            <i class="fas fa-paper-plane"></i> Sent
                        </div>
                    </div>
                </div>
                <div class="mail-list-pane">
                    <div class="mail-list-header">
                        <h3>${view === 'inbox' ? 'Inbox' : 'Sent'}</h3>
                        <button class="mail-compose-btn" onclick="window.showComposeMail()" title="New Message">
                            <i class="fas fa-edit"></i>
                        </button>
                    </div>
                    <div class="mail-items-list">
                        ${mailListHtml || '<div class="mac-empty-state">No messages</div>'}
                    </div>
                </div>
                <div class="mail-content-pane" id="mail-content-pane">
                    ${contentPaneHtml}
                </div>
            </div>
        `;
    });
};

window.selectMail = function(id) {
    window.selectedMailId = id;
    window.renderMailApp(window.currentMailView, false);
};

window.showComposeMail = function() {
    const content = document.getElementById('mail-content-pane');
    if (!content) return;

    // Get list of local departments for the "To" field
    let depts = window.currentDeptData && window.currentDeptData.nodes 
        ? window.currentDeptData.nodes.filter(n => n.type === 'department' && n.id !== window.currentJobName)
        : [];
    
    let localOptions = depts.map(d => `<option value="${d.id}">${d.label} (EMS/FIRE)</option>`).join('');

    // Add external departments from plt_departments if any
    let externalOptions = "";
    if (window.externalDepts && window.externalDepts.length > 0) {
        externalOptions = window.externalDepts
            .filter(d => d.id !== window.currentJobName)
            .map(d => `<option value="${d.id}">${d.label} (EXTERNAL)</option>`).join('');
    }

    content.innerHTML = `
        <div class="mail-compose-pane">
            <div class="mail-compose-field">
                <label>To:</label>
                <select id="mail-to">
                    <option value="" disabled selected>Select Department</option>
                    <optgroup label="Emergency Services">
                        ${localOptions}
                    </optgroup>
                    ${externalOptions ? `<optgroup label="Government Departments">${externalOptions}</optgroup>` : ""}
                </select>
            </div>
            <div class="mail-compose-field">
                <label>Subject:</label>
                <input type="text" id="mail-subject" placeholder="Enter subject">
            </div>
            <div class="mail-compose-field">
                <label>Image URL:</label>
                <input type="text" id="mail-image-url" placeholder="Paste image link (optional)">
            </div>
            <textarea class="mail-compose-body" id="mail-body" placeholder="Type your message here..."></textarea>
            <div class="mail-compose-footer">
                <button class="mail-cancel-btn" onclick="window.renderMailApp(window.currentMailView, false)">Cancel</button>
                <button class="mail-send-btn" onclick="window.sendMail()">Send</button>
            </div>
        </div>
    `;
};

window.sendMail = function() {
    const to = document.getElementById('mail-to').value;
    const subject = document.getElementById('mail-subject').value;
    const message = document.getElementById('mail-body').value;
    const imageUrl = document.getElementById('mail-image-url').value;

    if (!to) return window.showNotification('Error', null, 'Please select a recipient department');
    if (!message) return window.showNotification('Error', null, 'Please enter a message');

    fetch(`https://${GetParentResourceName()}/amb_sendMail`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            senderDept: window.currentJobName,
            receiverDept: to,
            subject: subject,
            message: message,
            imageUrl: imageUrl
        })
    }).then(() => {
        window.renderMailApp('sent');
    });
};

window.quickHire = function(playerId, name) {
    fetch(`https://${GetParentResourceName()}/amb_hirePlayer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            playerId: playerId,
            job: window.currentJobName,
            grade: 0
        })
    }).then(() => {
        window.renderMembersApp('main', false);
    });
};

// --- HEALTH MDT LOGIC ---
window.selectedPatientCid = null;
window.mdtActiveTab = 'overview';
window.mdtPatients = [];

window.getMDTAppHTML = function() {
    return `
        <div class="mdt-app-container">
            <div class="mdt-sidebar">
                <div class="mdt-search-wrapper">
                    <div class="mdt-search-input-group">
                        <i class="fas fa-search"></i>
                        <input type="text" id="mdt-search-input" placeholder="Search Patients..." onkeyup="window.searchMDTPatients()">
                    </div>
                </div>
                <div class="mdt-patient-list" id="mdt-patient-list">
                    <div class="mdt-empty-state" style="padding: 20px; font-size: 13px;">
                        Enter a name, CID, or phone number to begin.
                    </div>
                </div>
            </div>
            <div class="mdt-content-pane" id="mdt-content-pane">
                <div class="mdt-empty-state">
                    <i class="fas fa-heart-pulse"></i>
                    <p>Select a patient to view files</p>
                </div>
            </div>
        </div>
    `;
};

window.renderMDTApp = function(containerId = 'mac-app-container-safari', showLoader = true) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (showLoader) container.innerHTML = `<div class="mac-loader"></div>`;

    container.innerHTML = window.getMDTAppHTML();
};

window.searchMDTPatients = function(isRefresh = false) {
    const input = document.getElementById('mdt-search-input');
    const query = input ? input.value : "";
    const list = document.getElementById('mdt-patient-list');
    if (!list) return;

    if (query.length < 2 && !isRefresh) {
        list.innerHTML = '<div class="mdt-empty-state" style="padding: 20px; font-size: 13px;">Enter a name, CID, or phone number to begin.</div>';
        return;
    }

    if (!isRefresh) {
        list.innerHTML = '<div class="mdt-empty-state" style="padding: 20px; font-size: 13px;"><i class="fas fa-spinner fa-spin"></i> Searching...</div>';
    }

    console.log("[MDT] Sending search request for query:", query);

    fetch(`https://${GetParentResourceName()}/amb_searchPatients`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: query || (window.selectedPatientCid || "") })
    })
    .then(r => r.json())
    .then(results => {
        console.log("[MDT] Received search results:", results);
        window.mdtPatients = results || [];
        if (!results || results.length === 0) {
            list.innerHTML = '<div class="mdt-empty-state" style="padding: 20px; font-size: 13px;">No patients found matching "' + query + '".</div>';
            return;
        }

        list.innerHTML = results.map(p => `
            <div class="mdt-patient-card ${p.cid === window.selectedPatientCid ? 'active' : ''}" onclick="window.viewPatientProfile('${p.cid}')">
                <div class="p-name">${p.name || "Unknown"}</div>
                <div class="p-meta">CID: ${p.cid} • ${p.phone || 'No Phone'}</div>
            </div>
        `).join('');
    })
    .catch(err => {
        console.error("[MDT] Search Error:", err);
        list.innerHTML = '<div class="mdt-empty-state" style="padding: 20px; font-size: 13px; color: #ff3b30;">Search failed.</div>';
    });
};

window.viewPatientProfile = function(cid) {
    window.selectedPatientCid = cid;
    const content = document.getElementById('mdt-content-pane');
    if (!content) return;

    // Refresh list to show active state (don't show "Searching..." text)
    window.searchMDTPatients(true);

    content.innerHTML = `<div class="mac-loader"></div>`;

    fetch(`https://${GetParentResourceName()}/amb_getPatientDetails`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cid })
    })
    .then(r => r.json())
    .then(data => {
        window.currentPatientData = data;
        window.renderPatientDetails();
    })
    .catch(err => {
        console.error("MDT Profile Fetch Error:", err);
        content.innerHTML = '<div class="mdt-empty-state"><p>Failed to load profile details.</p></div>';
    });
};

window.renderPatientDetails = function() {
    const content = document.getElementById('mdt-content-pane');
    const data = window.currentPatientData;
    if (!content || !data) return;

    const tab = window.mdtActiveTab;

    let tabContent = "";
    if (tab === 'overview') {
        const knownAllergy = data.allergies || "None";
        const notes = data.medical_notes || "No additional medical history notes recorded.";

        tabContent = `
            <div class="mdt-info-grid">
                <div class="mdt-info-card"><label>Citizen ID</label><span>${data.cid}</span></div>
                <div class="mdt-info-card"><label>Phone Number</label><span>${data.phone || 'N/A'}</span></div>
                <div class="mdt-info-card"><label>Blood Type</label><span>${data.blood_type || 'Unknown'}</span></div>
                <div class="mdt-info-card"><label>Birth Date</label><span>${data.dob || 'Unknown'}</span></div>
                <div class="mdt-info-card"><label>Gender</label><span>${data.gender || 'Unknown'}</span></div>
                <div class="mdt-info-card"><label>Insurance</label><span style="color: ${data.insurance ? '#34c759' : '#ff3b30'}">${data.insurance ? 'ACTIVE' : 'NONE'}</span></div>
            </div>

            <div class="mdt-section-title"><i class="fas fa-biohazard"></i> KNOWN ALLERGY</div>
            <div class="mdt-history-item" style="border-left: 4px solid #ff3b30;">
                <div class="mdt-history-body" style="font-weight: 700; color: #ff3b30;">${knownAllergy}</div>
            </div>
            <div class="mdt-history-item" style="background: #fdfdfd;">
                <div class="intranet-input-group">
                    <label>Update Known Allergy (EMS)</label>
                    <input type="text" id="mdt-known-allergy-input" maxlength="120" placeholder="None">
                </div>
                <div class="form-footer" style="margin-top: 10px;">
                    <button class="intranet-btn-sm primary" onclick="window.updatePatientKnownAllergy()">Save Allergy</button>
                </div>
            </div>

            <div class="mdt-section-title"><i class="fas fa-file-invoice"></i> PHYSICIAN NOTES</div>
            <div class="mdt-history-item" style="background: #fdfdfd;">
                <div class="mdt-history-body">${notes}</div>
            </div>
        `;
    } else if (tab === 'history') {
        const pcrLogs = (data.pcrs || []).map(p => `
            <div class="mdt-history-item">
                <div class="mdt-history-header">
                    <span>${p.author}</span>
                    <span>${p.date}</span>
                </div>
                <div class="mdt-history-title">Condition: ${p.condition}</div>
                <div class="mdt-history-body">${p.treatment}</div>
            </div>
        `).join('') || '<div class="mdt-empty-state"><p>No Patient Care Reports on file.</p></div>';

        tabContent = `
            <div class="mdt-section-title"><i class="fas fa-clock-rotate-left"></i> TREATMENT HISTORY</div>
            ${pcrLogs}
        `;
    } else if (tab === 'imaging') {
        const xrayLogs = (data.xrays || []).map(x => `
            <div class="mdt-history-item">
                <div class="mdt-history-header">
                    <span>${x.date}</span>
                    <span style="color: #ff9500; font-weight: 800;">DIAGNOSTIC SCAN</span>
                </div>
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 10px;">
                    ${x.injuries.map(inj => `
                        <div style="font-size: 12px; background: #fff5f5; padding: 6px; border-radius: 6px; border: 1px solid #ffd1d1;">
                            <strong style="color: #ff3b30;">${inj.part.replace('Bone_', '').toUpperCase()}</strong>: ${inj.type.toUpperCase()}
                        </div>
                    `).join('')}
                </div>
            </div>
        `).join('') || '<div class="mdt-empty-state"><p>No X-Ray scans recorded.</p></div>';

        tabContent = `
            <div class="mdt-section-title"><i class="fas fa-x-ray"></i> RADIOLOGY LOGS</div>
            ${xrayLogs}
        `;
    } else if (tab === 'prescriptions') {
        // Need to add prescription log to server detail fetch
        const prescs = (data.prescriptions || []).map(pr => `
            <div class="mdt-history-item">
                <div class="mdt-history-header">
                    <span>Dr. ${pr.author}</span>
                    <span>${pr.date}</span>
                </div>
                <div class="mdt-history-title">${pr.item_label} (Qty: ${pr.quantity})</div>
                <div class="mdt-history-body" style="font-style: italic;">Notes: ${pr.notes}</div>
            </div>
        `).join('') || '<div class="mdt-empty-state"><p>No active or past prescriptions.</p></div>';

        tabContent = `
            <div class="mdt-section-title"><i class="fas fa-prescription"></i> PHARMACEUTICAL RECORDS</div>
            ${prescs}
        `;
    }

    content.innerHTML = `
        <div class="mdt-profile-header">
            <div class="mdt-profile-avatar">${data.name.charAt(0)}</div>
            <div class="mdt-profile-info">
                <h1>${data.name}</h1>
                <p>CID: ${data.cid} • Phone: ${data.phone || 'N/A'}</p>
            </div>
        </div>
        <div class="mdt-profile-tabs">
            <div class="mdt-tab ${tab === 'overview' ? 'active' : ''}" onclick="window.switchMDTTab('overview')">Overview</div>
            <div class="mdt-tab ${tab === 'history' ? 'active' : ''}" onclick="window.switchMDTTab('history')">History</div>
            <div class="mdt-tab ${tab === 'imaging' ? 'active' : ''}" onclick="window.switchMDTTab('imaging')">Imaging</div>
            <div class="mdt-tab ${tab === 'prescriptions' ? 'active' : ''}" onclick="window.switchMDTTab('prescriptions')">Prescriptions</div>
        </div>
        <div class="mdt-profile-content">
            ${tabContent}
        </div>
    `;

    if (tab === 'overview') {
        const allergyInput = document.getElementById('mdt-known-allergy-input');
        if (allergyInput) {
            allergyInput.value = (data.allergies && data.allergies !== 'None') ? data.allergies : '';
        }
    }
};

window.switchMDTTab = function(tab) {
    window.mdtActiveTab = tab;
    window.renderPatientDetails();
};

window.updatePatientKnownAllergy = function() {
    const data = window.currentPatientData;
    if (!data || !data.cid) return;

    const allergyInput = document.getElementById('mdt-known-allergy-input');
    if (!allergyInput) return;

    const knownAllergy = (allergyInput.value || '').trim();

    fetch(`https://${GetParentResourceName()}/amb_updatePatientAllergy`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            cid: data.cid,
            known_allergy: knownAllergy
        })
    })
    .then(r => r.json())
    .then(result => {
        if (result && result.success) {
            window.currentPatientData.allergies = result.known_allergy || 'None';
            window.renderPatientDetails();
            if (typeof window.showNotification === 'function') {
                window.showNotification('Saved', null, 'Known allergy updated.');
            }
            return;
        }

        if (typeof window.showNotification === 'function') {
            window.showNotification('Update Failed', null, (result && result.message) || 'Unable to update allergy.');
        }
    })
    .catch(() => {
        if (typeof window.showNotification === 'function') {
            window.showNotification('Update Failed', null, 'Unable to update allergy.');
        }
    });
};

window.manageDivision = function(action, divId) {
    const name = action === 'create' ? document.getElementById('new-div-name').value : null;
    if (action === 'create' && (!name || name.trim() === '')) return;

    fetch(`https://${GetParentResourceName()}/manageDivision`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            action: action,
            deptId: window.currentJobName,
            name: name,
            divId: divId
        })
    }).then(() => {
        if (action === 'create') document.getElementById('new-div-name').value = '';
    });
};

// --- WARRANT LOGIC ---

window.editingWarrantId = null;
window.editingCaseId = null;

/* Removed Warrants, Cases, BOLOs */

window.toggleNewsForm = function() {
    const form = document.getElementById('inline-news-form');
    if (!form) return;

    if (form.style.display === 'none') {
        form.style.display = 'block';
        document.getElementById('btn-toggle-news-form').innerHTML = '<i class="fas fa-times"></i> CLOSE FORM';
        document.getElementById('news-title').value = '';
        document.getElementById('news-content').value = '';
    } else {
        form.style.display = 'none';
        document.getElementById('btn-toggle-news-form').innerHTML = '<i class="fas fa-plus"></i> NEW ARTICLE';
    }
};

window.submitNewsInline = function() {
    const title = document.getElementById('news-title').value;
    const content = document.getElementById('news-content').value;

    if (!title || !content) {
        if (!title) document.getElementById('news-title').style.borderColor = '#f85149';
        if (!content) document.getElementById('news-content').style.borderColor = '#f85149';
        return;
    }

    fetch(`https://${GetParentResourceName()}/amb_addNews`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, content })
    });

    window.toggleNewsForm();
};

window.deleteNews = function(id) {
    fetch(`https://${GetParentResourceName()}/amb_deleteNews`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(id)
    });
};

// PCR (Patient Care Report) Handlers
window.togglePCRForm = function() {
    const form = document.getElementById('inline-pcr-form');
    if (!form) return;
    
    if (form.style.display === 'none') {
        form.style.display = 'block';
        document.getElementById('btn-toggle-pcr-form').innerHTML = '<i class="fas fa-times"></i> CLOSE FORM';
        document.getElementById('pcr-patient').value = '';
        document.getElementById('pcr-condition').value = '';
        document.getElementById('pcr-treatment').value = '';
    } else {
        form.style.display = 'none';
        document.getElementById('btn-toggle-pcr-form').innerHTML = '<i class="fas fa-file-medical"></i> FILE NEW REPORT';
    }
};

window.submitPCRInline = function() {
    const patient = document.getElementById('pcr-patient').value;
    const condition = document.getElementById('pcr-condition').value;
    const treatment = document.getElementById('pcr-treatment').value;

    if (!patient || !condition || !treatment) {
        if (!patient) document.getElementById('pcr-patient').style.borderColor = '#f85149';
        if (!condition) document.getElementById('pcr-condition').style.borderColor = '#f85149';
        if (!treatment) document.getElementById('pcr-treatment').style.borderColor = '#f85149';
        return;
    }

    fetch(`https://${GetParentResourceName()}/amb_addPCR`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ patient, condition, treatment })
    });

    window.togglePCRForm();
};

// DMR (Digital Medical Records) Handlers
window.searchDMR = function() {
    const query = document.getElementById('dmr-search-input').value.toLowerCase();
    const container = document.getElementById('dmr-results-container');
    if (!container) return;

    if (query.length < 2) {
        container.innerHTML = '<div class="intra-empty">Enter at least 2 characters to search.</div>';
        return;
    }

    // We fetch all "known" players from the server to search
    fetch(`https://${GetParentResourceName()}/amb_searchDMR`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query })
    })
    .then(r => r.json())
    .then(results => {
        if (!results || results.length === 0) {
            container.innerHTML = '<div class="intra-empty">No matching medical records found.</div>';
            return;
        }

        container.innerHTML = results.map(r => `
            <div class="mac-member-card" onclick="window.viewDMRRecord('${r.cid}')">
                <div class="mac-member-info-left">
                    <div class="member-avatar-ios">${r.name.charAt(0)}</div>
                    <div class="member-details-ios">
                        <span class="member-name-ios">${r.name}</span>
                        <span class="ios-id-tag">CID: ${r.cid}</span>
                    </div>
                </div>
                <div class="mac-member-actions-slim">
                    <button class="ios-slim-btn"><i class="fas fa-folder-open"></i> <span>VIEW FILE</span></button>
                </div>
            </div>
        `).join('');
    });
};

window.viewDMRRecord = function(cid) {
    let modal = document.getElementById('mac-generic-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'mac-generic-modal';
        document.getElementById('boss-menu-container').appendChild(modal);
    }
    
    modal.className = 'mac-modal-overlay visible';
    modal.innerHTML = `<div class="mac-loader"></div>`;

    fetch(`https://${GetParentResourceName()}/amb_getDMRDetails`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cid })
    })
    .then(r => r.json())
    .then(data => {
        const pcrLogs = (data.pcrs || []).map(p => `
            <div class="report-log-item">
                <div class="report-log-header">
                    <span class="report-author">${p.author}</span>
                    <span class="report-date">${p.date}</span>
                </div>
                <div style="font-size: 13px; margin-top: 5px;">
                    <div style="color: #d32f2f; font-weight: 700; margin-bottom: 4px;">INCIDENT: ${p.condition}</div>
                    <div style="color: #666;">${p.treatment}</div>
                </div>
            </div>
        `).join('') || '<div class="mac-empty-state">No past incident reports found.</div>';

        const xrayLogs = (data.xrays || []).map(x => `
            <div class="report-log-item" style="border-left: 4px solid #ffcc00;">
                <div class="report-log-header">
                    <span class="report-author" style="color: #a30000;">X-RAY DIAGNOSIS</span>
                    <span class="report-date">${x.date}</span>
                </div>
                <div style="font-size: 12px; margin-top: 5px; display: grid; grid-template-columns: 1fr 1fr; gap: 5px;">
                    ${x.injuries.map(inj => `<div><span style="color: #888;">${inj.part.replace('Bone_', '').toUpperCase()}:</span> <span style="color: ${inj.type === 'fracture' ? '#d32f2f' : '#ff9f0a'}; font-weight: 700;">${inj.type.toUpperCase()}</span></div>`).join('')}
                </div>
            </div>
        `).join('') || '<div class="mac-empty-state">No X-Ray scans on record.</div>';

        modal.innerHTML = `
            <div class="mac-ios-modal" style="width: 500px; max-height: 80vh; border-top: 5px solid #a30000;">
                <div class="modal-header">
                    <h3 style="font-size: 22px; color: #a30000;">Medical File: ${data.name}</h3>
                    <p>CITIZEN ID: ${cid}</p>
                </div>
                <div class="modal-content mac-scroll-area">
                    <div class="modal-section-title" style="color: #a30000; border-bottom: 2px solid #a30000;">Incident History (PCRs)</div>
                    ${pcrLogs}
                    
                    <div class="modal-section-title" style="margin-top: 20px; color: #a30000; border-bottom: 2px solid #a30000;">Diagnostic Imaging (X-Rays)</div>
                    ${xrayLogs}
                </div>
                <div class="modal-footer" style="background: #f8f9fa;">
                    <button class="mac-btn-primary" onclick="window.closeMacModal()" style="width: 100%;">Close Record</button>
                </div>
            </div>
        `;
    });
};

window.closeMacModal = function() {
    const modal = document.getElementById('mac-generic-modal');
    if (modal) {
        modal.classList.remove('visible');
        setTimeout(() => {
            modal.innerHTML = '';
        }, 300);
    }
};

window.completeWarrant = function(id) {
    fetch(`https://${GetParentResourceName()}/completeWarrant`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(id)
    });
};

window.showReportModal = function(cid, name) {
    const memberData = (window.syncedMembers && window.syncedMembers[cid]) || {};
    const reports = memberData.ratings || [];
    
    let modal = document.getElementById('mac-generic-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'mac-generic-modal';
        document.getElementById('boss-menu-container').appendChild(modal);
    }
    
    modal.className = 'mac-modal-overlay visible';
    
    const renderStars = (rating) => {
        let stars = '';
        for (let i = 1; i <= 5; i++) {
            stars += `<i class="fas fa-star" style="color: ${i <= rating ? '#ffcc00' : '#ccc'}"></i>`;
        }
        return stars;
    };

    const reportsList = reports.map(r => `
        <div class="report-log-item">
            <div class="report-log-header">
                <span class="report-author">${r.author}</span>
                <span class="report-date">${r.date}</span>
                <span class="report-overall">${renderStars(r.overall)}</span>
            </div>
            <div class="report-scores-grid">
                <div class="score-item"><span>Knowledge:</span> ${r.knowledge}/5</div>
                <div class="score-item"><span>Comms:</span> ${r.communication}/5</div>
                <div class="score-item"><span>Situational:</span> ${r.situation_management}/5</div>
                <div class="score-item"><span>Decision:</span> ${r.decision_making}/5</div>
                <div class="score-item"><span>Reports:</span> ${r.report_writing}/5</div>
            </div>
        </div>
    `).join('');

    modal.innerHTML = `
        <div class="mac-ios-modal reports-modal">
            <div class="modal-header">
                <h3>Performance Reports</h3>
                <p>${name}</p>
            </div>
            <div class="modal-content">
                <div class="new-report-section">
                    <h4>Add New Report</h4>
                    <div class="rating-input-grid">
                        <div class="rating-field">
                            <label>Knowledge</label>
                            <input type="range" min="0" max="5" value="0" id="rate-knowledge" oninput="window.updateReportOverall()">
                            <span id="val-knowledge">0</span>
                        </div>
                        <div class="rating-field">
                            <label>Communication</label>
                            <input type="range" min="0" max="5" value="0" id="rate-communication" oninput="window.updateReportOverall()">
                            <span id="val-communication">0</span>
                        </div>
                        <div class="rating-field">
                            <label>Situation Mgmt</label>
                            <input type="range" min="0" max="5" value="0" id="rate-situation" oninput="window.updateReportOverall()">
                            <span id="val-situation">0</span>
                        </div>
                        <div class="rating-field">
                            <label>Decision Making</label>
                            <input type="range" min="0" max="5" value="0" id="rate-decision" oninput="window.updateReportOverall()">
                            <span id="val-decision">0</span>
                        </div>
                        <div class="rating-field">
                            <label>Report Writing</label>
                            <input type="range" min="0" max="5" value="0" id="rate-writing" oninput="window.updateReportOverall()">
                            <span id="val-writing">0</span>
                        </div>
                    </div>
                    <div class="overall-rating-display">
                        <span>Overall Rating:</span>
                        <div id="report-overall-stars">${renderStars(0)}</div>
                        <strong id="report-overall-value">0.0</strong>
                    </div>
                    <button class="mac-btn-primary full-width" onclick="window.submitOfficerReport('${cid}')">Submit Report</button>
                </div>
                <div class="reports-history-section">
                    <h4>History</h4>
                    <div class="reports-log-container">
                        ${reportsList || '<div class="mac-empty-state">No reports recorded.</div>'}
                    </div>
                </div>
            </div>
            <div class="modal-footer">
                <button class="mac-btn-secondary" onclick="window.closeMacModal()">Close</button>
            </div>
        </div>
    `;
};

window.updateReportOverall = function() {
    const k = parseInt(document.getElementById('rate-knowledge').value);
    const c = parseInt(document.getElementById('rate-communication').value);
    const s = parseInt(document.getElementById('rate-situation').value);
    const d = parseInt(document.getElementById('rate-decision').value);
    const w = parseInt(document.getElementById('rate-writing').value);

    document.getElementById('val-knowledge').innerText = k;
    document.getElementById('val-communication').innerText = c;
    document.getElementById('val-situation').innerText = s;
    document.getElementById('val-decision').innerText = d;
    document.getElementById('val-writing').innerText = w;

    const avg = ((k + c + s + d + w) / 5).toFixed(1);
    document.getElementById('report-overall-value').innerText = avg;
    
    // Update stars
    let stars = '';
    for (let i = 1; i <= 5; i++) {
        stars += `<i class="fas fa-star" style="color: ${i <= Math.round(avg) ? '#ffcc00' : '#ccc'}"></i>`;
    }
    document.getElementById('report-overall-stars').innerHTML = stars;
};

window.submitOfficerReport = function(cid) {
    const k = parseInt(document.getElementById('rate-knowledge').value);
    const c = parseInt(document.getElementById('rate-communication').value);
    const s = parseInt(document.getElementById('rate-situation').value);
    const d = parseInt(document.getElementById('rate-decision').value);
    const w = parseInt(document.getElementById('rate-writing').value);
    const overall = parseFloat(((k + c + s + d + w) / 5).toFixed(1));

    fetch(`https://${GetParentResourceName()}/submitOfficerReport`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            cid: cid,
            knowledge: k,
            communication: c,
            situation_management: s,
            decision_making: d,
            report_writing: w,
            overall: overall
        })
    }).then(() => {
        // Refresh player list and update modal
        fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        })
        .then(res => res.json())
        .then(players => {
            const p = players.find(player => player.cid === cid);
            if (p) window.showReportModal(cid, p.name);
            
            // Refresh the database tab view if open
            const membersWin = document.getElementById('mac-window-members');
            if (membersWin && !membersWin.classList.contains('hidden')) {
                window.renderMembersApp('main', false);
            }
        });
    });
};

const lapdMedals = [
    { id: 'LAPD-Medal-of-Valor', name: 'Medal of Valor' },
    { id: 'LAPD-Preservation-of-Life-Medal', name: 'Preservation of Life Medal' },
    { id: 'Medical-Distinguished-Service', name: 'Medical Distinguished Service Medal' },
    { id: 'Emergency-Response-Citation', name: 'Emergency Response Citation' },
    { id: 'Life-Saving-Medal', name: 'Life Saving Medal' },
    { id: 'LAPD-Purple-Heart-Ribbon', name: 'Purple Heart' },
    { id: 'Paramedic-Service-Medal', name: 'Paramedic Service Medal' },
    { id: 'Medical-Achievement-Medal', name: 'Medical Achievement Medal' },
    { id: 'Healthcare-Unit-Citation', name: 'Healthcare Unit Citation' },
    { id: 'Medical-Star', name: 'Medical Star' },
    { id: 'LAPD-Lifesaving-Medal', name: 'Lifesaving Medal' }
];

window.showHonorModal = function(cid, name) {
    // Get member data from syncedMembers or fetch it
    const memberData = (window.syncedMembers && window.syncedMembers[cid]) || {};
    const medals = Array.isArray(memberData.medals) ? memberData.medals : (typeof memberData.medals === 'object' ? Object.values(memberData.medals) : []);

    const activeHonors = medals.map((m, index) => `
        <div class="active-honor-item">
            <img src="img/${m.id}.webp" class="medal-icon-mini" onerror="this.src='img/members.png'">
            <div class="honor-info">
                <span class="honor-name">${m.name}</span>
                <span class="honor-date">${m.date || 'Unknown Date'}</span>
            </div>
            <button class="remove-honor-btn" onclick="window.removeMedal('${cid}', ${index}, '${name.replace(/'/g, "\\'")}')">
                <i class="fas fa-trash"></i>
            </button>
        </div>
    `).join('');

    const medalOptions = lapdMedals.map(m => {
        const imgPath = `img/${m.id}.webp`;
        return `
            <div class="medal-selection-item" onclick="window.awardMedal('${cid}', '${m.id}', '${m.name}')">
                <img src="${imgPath}" class="medal-icon-preview" onerror="this.onerror=null; this.src='img/members.png';">
                <div class="medal-info">
                    <span class="medal-name">${m.name}</span>
                    <span class="medal-description">LAPD OFFICIAL AWARD</span>
                </div>
            </div>
        `;
    }).join('');

    let modal = document.getElementById('mac-generic-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'mac-generic-modal';
        document.getElementById('boss-menu-container').appendChild(modal);
    }
    
    modal.className = 'mac-modal-overlay visible';
    modal.innerHTML = `
        <div class="mac-ios-modal">
            <div class="modal-header">
                <h3>Manage Honors & Medals</h3>
                <p>Personnel: ${name}</p>
            </div>
            <div class="modal-content">
                ${medals.length > 0 ? `
                    <div class="modal-section-title">ACTIVE HONORS</div>
                    <div class="active-honors-list">
                        ${activeHonors}
                    </div>
                ` : ''}
                <div class="modal-section-title">AWARD NEW MEDAL</div>
                <div class="medal-selection-list">
                    ${medalOptions}
                </div>
            </div>
            <div class="modal-footer">
                <button class="mac-btn-primary" onclick="window.closeMacModal()">Done</button>
            </div>
        </div>
    `;
};

window.awardMedal = function(cid, medalId, medalName) {
    fetch(`https://${GetParentResourceName()}/manageMember`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            cid: cid,
            action: 'honor',
            medalId: medalId,
            medalName: medalName,
            dept: window.currentJobName
        })
    }).then(() => {
        // Refresh player data and modal
        fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        })
        .then(res => res.json())
        .then(players => {
            const p = players.find(player => player.cid === cid);
            if (p) window.showHonorModal(cid, p.name);
            window.renderDepartmentMembers(false);
        });
    });
};

window.removeMedal = function(cid, index, name) {
    fetch(`https://${GetParentResourceName()}/manageMember`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            cid: cid,
            action: 'remove_honor',
            index: index,
            dept: window.currentJobName
        })
    }).then(() => {
        // Refresh player data and modal
        fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        })
        .then(res => res.json())
        .then(players => {
            const p = players.find(player => player.cid === cid);
            if (p) window.showHonorModal(cid, name);
            window.renderDepartmentMembers(false);
        });
    });
};

window.showDivisionModal = function(cid, name) {
    const divisions = (window.currentDeptData.divisions && window.currentDeptData.divisions[window.currentJobName]) || [];
    const memberDivs = (window.syncedMembers && window.syncedMembers[cid] && window.syncedMembers[cid].divisions) || [];
    
    const divOptions = divisions.map(d => {
        const isActive = memberDivs.includes(d.id);
        return `
            <div class="div-toggle-item ${isActive ? 'active' : ''}" onclick="window.toggleMemberDivision('${cid}', '${d.id}')">
                <span>${d.name}</span>
                <i class="fas ${isActive ? 'fa-check-circle' : 'fa-circle'}"></i>
            </div>
        `;
    }).join('');

    let modal = document.getElementById('mac-generic-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'mac-generic-modal';
        document.getElementById('boss-menu-container').appendChild(modal);
    }
    
    modal.className = 'mac-modal-overlay visible';
    modal.innerHTML = `
        <div class="mac-ios-modal">
            <div class="modal-header">
                <h3>Manage Divisions</h3>
                <p>${name}</p>
            </div>
            <div class="modal-content">
                ${divOptions.length > 0 ? divOptions : '<div class="mac-empty-state">No divisions available.</div>'}
            </div>
            <div class="modal-footer">
                <button class="mac-btn-primary" onclick="window.closeMacModal()">Done</button>
            </div>
        </div>
    `;
};

window.toggleMemberDivision = function(cid, divId) {
    fetch(`https://${GetParentResourceName()}/toggleMemberDivision`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cid, divId })
    }).then(() => {
        fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        })
        .then(res => res.json())
        .then(players => {
            const p = players.find(player => player.cid === cid);
            if (p) window.showDivisionModal(cid, p.name);
            
            const deptWin = document.getElementById('mac-window-dept');
            if (deptWin && !deptWin.classList.contains('hidden')) {
                window.openMacApp('dept_manager');
            }
        });
    });
};

window.closeMacModal = function() {
    const modal = document.getElementById('mac-generic-modal');
    if (modal) modal.classList.remove('visible');
};

// Clock Logic
setInterval(() => {
    const clock = document.getElementById('mac-clock');
    if (clock) {
        const now = new Date();
        const timeStr = now.toLocaleTimeString('en-US', { 
            hour: 'numeric', 
            minute: '2-digit',
            hour12: true 
        });
        const dayStr = now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
        clock.innerText = `${dayStr}  ${timeStr}`;
    }
}, 1000);

// Key Handling
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        const container = document.getElementById('boss-menu-container');
        if (container && container.classList.contains('visible')) {
            window.shutdownPC();
        }
    }
});

// --- Draggable Windows Functionality ---
document.addEventListener('DOMContentLoaded', () => {
    const getDesktopScale = (desktopEl) => {
        if (!desktopEl) return 1;
        const transform = window.getComputedStyle(desktopEl).transform;
        if (!transform || transform === 'none') return 1;

        const match2d = transform.match(/matrix\(([^)]+)\)/);
        if (match2d) {
            const parts = match2d[1].split(',').map(v => parseFloat(v.trim()));
            if (parts.length >= 1 && Number.isFinite(parts[0]) && parts[0] > 0) {
                return parts[0];
            }
        }

        const match3d = transform.match(/matrix3d\(([^)]+)\)/);
        if (match3d) {
            const parts = match3d[1].split(',').map(v => parseFloat(v.trim()));
            if (parts.length >= 1 && Number.isFinite(parts[0]) && parts[0] > 0) {
                return parts[0];
            }
        }

        return 1;
    };

    const setupDraggable = (winId) => {
        const win = document.getElementById(`mac-window-${winId}`);
        if (!win) return;
        const header = win.querySelector('.win-header');
        if (!header) return;

        let isDragging = false;
        let offsetX, offsetY;

        // Bring to front on click
        win.addEventListener('mousedown', () => {
            win.style.zIndex = ++window.highestZIndex;
            
            // Update active app name based on data-app attribute
            const activeAppName = document.getElementById('active-app-name');
            const appName = win.getAttribute('data-app');
            if (activeAppName && appName) {
                activeAppName.innerText = appName;
            }
        });

        header.addEventListener('mousedown', (e) => {
            if (e.target.classList.contains('win-close')) return;
            const desktop = document.querySelector('.macos-desktop');
            if (!desktop) return;

            const desktopRect = desktop.getBoundingClientRect();
            const scale = getDesktopScale(desktop);
            const rect = win.getBoundingClientRect();

            const mouseXLogical = (e.clientX - desktopRect.left) / scale;
            const mouseYLogical = (e.clientY - desktopRect.top) / scale;
            const winLeftLogical = Number.isFinite(parseFloat(win.style.left))
                ? parseFloat(win.style.left)
                : (rect.left - desktopRect.left) / scale;
            const winTopLogical = Number.isFinite(parseFloat(win.style.top))
                ? parseFloat(win.style.top)
                : (rect.top - desktopRect.top) / scale;

            isDragging = true;
            offsetX = mouseXLogical - winLeftLogical;
            offsetY = mouseYLogical - winTopLogical;
            header.style.cursor = 'grabbing';
            e.preventDefault();
        });

        document.addEventListener('mousemove', (e) => {
            if (!isDragging) return;
            const desktop = document.querySelector('.macos-desktop');
            if (!desktop) return;
            const desktopRect = desktop.getBoundingClientRect();
            const scale = getDesktopScale(desktop);

            let x = (e.clientX - desktopRect.left) / scale - offsetX;
            let y = (e.clientY - desktopRect.top) / scale - offsetY;

            const desktopLogicalWidth = desktopRect.width / scale;
            const desktopLogicalHeight = desktopRect.height / scale;

            // Keep window within the desktop area bounds
            x = Math.max(0, Math.min(x, desktopLogicalWidth - win.offsetWidth));
            y = Math.max(0, Math.min(y, desktopLogicalHeight - win.offsetHeight));

            win.style.left = x + 'px';
            win.style.top = y + 'px';
        });

        document.addEventListener('mouseup', () => {
            isDragging = false;
            header.style.cursor = 'default';
        });
    };

    setupDraggable('dept');
    setupDraggable('members');
    setupDraggable('finances');
    setupDraggable('safari');
    setupDraggable('calculator');
    setupDraggable('clock');
    setupDraggable('mail');
    setupDraggable('settings');
});

// Calculator Logic
let calcCurrentValue = '0';
let calcPreviousValue = null;
let calcOperator = null;
let calcWaitingForNextValue = false;

window.calcInput = function(value) {
    const display = document.getElementById('calc-display');
    if (!display) return;

    if (value === 'AC') {
        calcCurrentValue = '0';
        calcPreviousValue = null;
        calcOperator = null;
        calcWaitingForNextValue = false;
    } else if (value === '+/-') {
        calcCurrentValue = (parseFloat(calcCurrentValue) * -1).toString();
    } else if (value === '%') {
        calcCurrentValue = (parseFloat(calcCurrentValue) / 100).toString();
    } else if (['+', '-', '*', '/'].includes(value)) {
        if (calcOperator && !calcWaitingForNextValue) {
            calcCurrentValue = window.calcPerformCalculation();
        }
        calcOperator = value;
        calcPreviousValue = calcCurrentValue;
        calcWaitingForNextValue = true;
    } else if (value === '=') {
        if (calcOperator && calcPreviousValue !== null) {
            calcCurrentValue = window.calcPerformCalculation();
            calcOperator = null;
            calcPreviousValue = null;
            calcWaitingForNextValue = false;
        }
    } else if (value === '.') {
        if (!calcCurrentValue.includes('.')) {
            calcCurrentValue += '.';
        }
    } else {
        // Number input
        if (calcWaitingForNextValue) {
            calcCurrentValue = value;
            calcWaitingForNextValue = false;
        } else {
            calcCurrentValue = calcCurrentValue === '0' ? value : calcCurrentValue + value;
        }
    }

    display.innerText = calcCurrentValue.substring(0, 10);
};

window.calcPerformCalculation = function() {
    const prev = parseFloat(calcPreviousValue);
    const curr = parseFloat(calcCurrentValue);
    if (isNaN(prev) || isNaN(curr)) return calcCurrentValue;

    let result = 0;
    switch (calcOperator) {
        case '+': result = prev + curr; break;
        case '-': result = prev - curr; break;
        case '*': result = prev * curr; break;
        case '/': result = prev / curr; break;
    }
    return result.toString();
};

// --- Dynamic MacOS Dock Magnification ---
document.addEventListener('DOMContentLoaded', () => {
    const dock = document.querySelector('.mac-dock');
    if (!dock) return;

    const dockItems = dock.querySelectorAll('.dock-item');
    const maxScale = 1.35; // Reduced from 1.8 for a more subtle effect
    const range = 100;     // Reduced from 150 for a tighter magnification area

    dock.addEventListener('mousemove', (e) => {
        const mouseX = e.clientX;

        dockItems.forEach(item => {
            const rect = item.getBoundingClientRect();
            const centerX = rect.left + rect.width / 2;
            const dist = Math.abs(mouseX - centerX);

            if (dist < range) {
                // Calculation for smooth curve (Gaussian-like)
                const scale = 1 + (maxScale - 1) * (1 - dist / range);
                const lift = (scale - 1) * 20;
                
                // Calculate margin with a smoother factor to avoid jumps at the edge of 'range'
                const extraWidth = (50 * scale - 50) / 2;
                const smoothnessFactor = Math.pow(1 - dist / range, 2); // Squared for a softer entrance
                const marginExtra = extraWidth + (smoothnessFactor * 6);
                
                item.style.margin = `0 ${marginExtra}px`;
                item.style.transform = `scale(${scale}) translateY(-${lift}px)`;
                item.style.zIndex = Math.round(scale * 10);
            } else {
                item.style.margin = '0';
                item.style.transform = 'scale(1) translateY(0)';
                item.style.zIndex = '1';
            }
        });
    });

    dock.addEventListener('mouseleave', () => {
        dockItems.forEach(item => {
            item.style.margin = '0';
            item.style.transform = 'scale(1) translateY(0)';
            item.style.zIndex = '1';
        });
    });
});

// Add animations to CSS via JS
const style = document.createElement('style');
style.innerHTML = `
    @keyframes scaleIn {
        from { transform: scale(0.9); opacity: 0; }
        to { transform: scale(1); opacity: 1; }
    }
    @keyframes scaleOut {
        from { transform: scale(1); opacity: 1; }
        to { transform: scale(0.9); opacity: 0; }
    }
`;
document.head.appendChild(style);

