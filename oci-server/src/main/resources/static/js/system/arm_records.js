// Configuration
const CONFIG = {
    pageSize: 10,
    refreshInterval: 5 * 60 * 1000,
    maxPaginationPages: 5
};

// State Management
const STATE = {
    map: null,
    markers: {},
    allRegions: [],
    openRegions: [],
    myRegions: [],
    currentPage: 1,
    currentView: 'arm',
    regionMap: {},
    mapInitialized: false
};

// Region Coordinates Data
const REGION_COORDINATES = {
    "af-johannesburg-1": { lat: -26.2041, lng: 28.0473 },
    "af-casablanca-1": { lat: 33.5731, lng: -7.5898 },
    "ap-chuncheon-1": { lat: 37.8747, lng: 127.7342 },
    "ap-hyderabad-1": { lat: 17.3850, lng: 78.4867 },
    "ap-melbourne-1": { lat: -37.8136, lng: 144.9631 },
    "ap-mumbai-1": { lat: 19.0760, lng: 72.8777 },
    "ap-osaka-1": { lat: 34.6937, lng: 135.5023 },
    "ap-seoul-1": { lat: 37.5665, lng: 126.9780 },
    "ap-kulai-2": { lat: 1.6629, lng: 103.5999 },
    "ap-singapore-1": { lat: 1.3521, lng: 103.8198 },
    "ap-singapore-2": { lat: 1.3000, lng: 103.7500 },
    "ap-sydney-1": { lat: -33.8688, lng: 151.2093 },
    "ap-tokyo-1": { lat: 35.6762, lng: 139.6503 },
    "ap-batam-1": { lat: 1.1074, lng: 104.0300 },
    "ca-montreal-1": { lat: 45.5017, lng: -73.5673 },
    "ca-toronto-1": { lat: 43.6532, lng: -79.3832 },
    "eu-amsterdam-1": { lat: 52.3676, lng: 4.9041 },
    "eu-frankfurt-1": { lat: 50.1109, lng: 8.6821 },
    "eu-jovanovac-1": { lat: 44.2768, lng: 20.5896 },
    "eu-madrid-1": { lat: 40.4168, lng: -3.7038 },
    "eu-madrid-3": { lat: 40.4168, lng: -3.7038 },
    "eu-marseille-1": { lat: 43.2965, lng: 5.3698 },
    "eu-milan-1": { lat: 45.4642, lng: 9.1900 },
    "eu-turin-1": { lat: 45.0703, lng: 7.6869 },
    "eu-paris-1": { lat: 48.8566, lng: 2.3522 },
    "eu-stockholm-1": { lat: 59.3293, lng: 18.0686 },
    "eu-zurich-1": { lat: 47.3769, lng: 8.5417 },
    "il-jerusalem-1": { lat: 31.7683, lng: 35.2137 },
    "me-abudhabi-1": { lat: 24.4539, lng: 54.3773 },
    "me-dubai-1": { lat: 25.2048, lng: 55.2708 },
    "me-jeddah-1": { lat: 21.4858, lng: 39.1925 },
    "mx-monterrey-1": { lat: 25.6866, lng: -100.3161 },
    "mx-queretaro-1": { lat: 20.5888, lng: -100.3899 },
    "sa-bogota-1": { lat: 4.7110, lng: -74.0721 },
    "sa-santiago-1": { lat: -33.4489, lng: -70.6693 },
    "sa-saopaulo-1": { lat: -23.5505, lng: -46.6333 },
    "sa-vinhedo-1": { lat: -23.0304, lng: -46.9834 },
    "uk-cardiff-1": { lat: 51.4816, lng: -3.1791 },
    "uk-london-1": { lat: 51.5074, lng: -0.1278 },
    "us-ashburn-1": { lat: 39.0438, lng: -77.4874 },
    "us-chicago-1": { lat: 41.8781, lng: -87.6298 },
    "us-phoenix-1": { lat: 33.4484, lng: -112.0740 },
    "us-sanjose-1": { lat: 37.3382, lng: -121.8863 },
    "sa-valparaiso-1": { lat: -33.0472, lng: -71.6127 }
};

// Continent Mapping
const CONTINENT_MAP = {
    "ap-": "asia",
    "eu-": "europe",
    "uk-": "europe",
    "il-": "europe",
    "me-": "middle-east",
    "af-": "middle-east",
    "us-": "america-north",
    "ca-": "america-north",
    "mx-": "america-north",
    "sa-": "america-south"
};

// Utility Functions
const utils = {
    formatDateTime(dateTimeStr) {
        if (!dateTimeStr) return '--';
        return new Date(dateTimeStr).toLocaleString('zh-CN');
    },

    getContinent(regionCode) {
        for (const prefix in CONTINENT_MAP) {
            if (regionCode.startsWith(prefix)) {
                return CONTINENT_MAP[prefix];
            }
        }
        return "other";
    },

    createStatusBadge(isOpen) {
        if (isOpen) {
            return '<span class="status-badge status-open">已放货</span>';
        } else {
            return '<span class="status-badge status-closed">未放货</span>';
        }
    }
};

// Map Management
const mapManager = {
    initMap() {
        STATE.map = L.map('world-map', {
            center: [20, 0],
            zoom: 2,
            minZoom: 2,
            maxZoom: 5,
            zoomControl: true,
            attributionControl: false
        });

        // 使用浅色底图
        L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png', {
            attribution: false,
            subdomains: 'abcd',
        }).addTo(STATE.map);

        // 初始化所有区域的标记
        this.initializeMarkers();
    },

    initializeMarkers() {
        // 创建所有区域的灰色标记
        for (const regionCode in REGION_COORDINATES) {
            const region = REGION_COORDINATES[regionCode];
            const marker = this.createMarker(region, regionCode);
            STATE.markers[regionCode] = marker;
        }
    },

    createMarker(region, regionCode) {
        // 创建灰色标记 - 增大圆点尺寸
        const markerHtml = '<div class="marker-inactive"></div>';
        const customIcon = L.divIcon({
            className: '',
            html: markerHtml,
            iconSize: [14, 14], // 增大灰色圆点尺寸
            iconAnchor: [6, 6]
        });

        const marker = L.marker([region.lat, region.lng], {
            icon: customIcon,
            zIndexOffset: 1000
        }).addTo(STATE.map);

        // 创建默认弹出内容
        const popupContent = this.createPopupContent(regionCode);
        marker.bindPopup(popupContent, {
            offset: [0, -6],
            closeButton: false
        });

        return marker;
    },

    createPopupContent(regionCode) {
        return '<div class="region-popup">' +
            '<h4>' + (STATE.regionMap[regionCode] || regionCode) + '</h4>' +
            '<div class="info-row">' +
            '<span>区域代码:</span>' +
            '<span>' + regionCode + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>状态:</span>' +
            '<span>未放货</span>' +
            '</div>' +
            '</div>';
    },

    updateMarkers(regionData) {
        console.log('更新标记，当前视图:', STATE.currentView, '数据:', regionData);

        // 重置所有标记为灰色
        for (const regionCode in STATE.markers) {
            const marker = STATE.markers[regionCode];
            const markerHtml = '<div class="marker-inactive"></div>';
            const customIcon = L.divIcon({
                className: '',
                html: markerHtml,
                iconSize: [14, 14],
                iconAnchor: [6, 6]
            });
            marker.setIcon(customIcon);

            // 恢复默认弹出内容
            const popupContent = this.createPopupContent(regionCode);
            marker.bindPopup(popupContent, {
                offset: [0, -6],
                closeButton: false
            });
        }

        if (STATE.currentView === 'my') {
            // 显示我的区域
            regionData.forEach(region => {
                const regionCode = region.region;
                if (STATE.markers[regionCode]) {
                    const marker = STATE.markers[regionCode];

                    // 设置为绿色闪烁标记
                    const markerHtml = '<div class="marker-my-region"></div>';
                    const customIcon = L.divIcon({
                        className: '',
                        html: markerHtml,
                        iconSize: [16, 16],
                        iconAnchor: [8, 8]
                    });
                    marker.setIcon(customIcon);

                    // 简化的弹出内容
                    const popupContent = this.createSimplePopupContent(regionCode);
                    marker.bindPopup(popupContent, {
                        offset: [0, -8],
                        closeButton: false
                    });
                }
            });

            // 更新统计数据
            document.getElementById('map-arm-count').textContent = regionData.length;
            const regionCardTitle = document.querySelector('.region-card h3');
            if (regionCardTitle) {
                regionCardTitle.innerHTML = '数量: <span class="arm-counter" id="map-arm-count">' + regionData.length + '</span>';
            }
        } else {
            // 显示ARM放货区域（原有逻辑）
            const openRegionMap = {};
            if (regionData && regionData.length > 0) {
                regionData.forEach(region => {
                    if (region && region.region && region.openCount > 0) {
                        openRegionMap[region.region] = region;
                    }
                });
            }

            for (const regionCode in openRegionMap) {
                const marker = STATE.markers[regionCode];
                if (marker) {
                    // 设置为橙色动态标记
                    const markerHtml = '<div class="marker-active"></div>';
                    const customIcon = L.divIcon({
                        className: '',
                        html: markerHtml,
                        iconSize: [16, 16],
                        iconAnchor: [8, 8]
                    });
                    marker.setIcon(customIcon);

                    // 详细弹出内容
                    const popupContent = this.createDetailedPopupContent(regionCode, openRegionMap[regionCode]);
                    marker.bindPopup(popupContent, {
                        offset: [0, -8],
                        closeButton: false
                    });
                }
            }

            // 更新统计数据
            const openCount = Object.keys(openRegionMap).length;
            document.getElementById('map-arm-count').textContent = openCount;
            const regionCardTitle = document.querySelector('.region-card h3');
            if (regionCardTitle) {
                regionCardTitle.innerHTML = '数量: <span class="arm-counter" id="map-arm-count">' + openCount + '</span>';
            }
        }
    },

    createSimplePopupContent(regionCode) {
        return '<div class="region-popup">' +
            '<h4>' + (STATE.regionMap[regionCode] || regionCode) + '</h4>' +
            '<div class="info-row">' +
            '<span>区域代码:</span>' +
            '<span>' + regionCode + '</span>' +
            '</div>' +
            '</div>';
    },

    createDetailedPopupContent(regionCode, regionData) {
        return '<div class="region-popup">' +
            '<h4>' + (STATE.regionMap[regionCode] || regionCode) + '</h4>' +
            '<div class="info-row">' +
            '<span>区域代码:</span>' +
            '<span>' + regionCode + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>状态:</span>' +
            '<span style="color: var(--accent-green);">已放货</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>架构类型:</span>' +
            '<span>' + regionData.architectureType + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>总开机数量:</span>' +
            '<span>' + regionData.openCount + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>当月开机数量:</span>' +
            '<span>' + (regionData.monthlyOpenCount || 0) + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>开机时间:</span>' +
            '<span>' + utils.formatDateTime(regionData.openTime) + '</span>' +
            '</div>' +
            '<div class="info-row">' +
            '<span>最后开机时间:</span>' +
            '<span>' + utils.formatDateTime(regionData.lastNotifyTime) + '</span>' +
            '</div>' +
            '</div>';
    }
};

// Table Management
const tableManager = {
    updateTable() {
        const searchTerm = document.getElementById('region-search').value.toLowerCase();
        const continentFilter = document.getElementById('continent-filter').value;
        const statusFilter = document.getElementById('status-filter').value;

        const filteredRegions = this.getFilteredRegions(searchTerm, continentFilter, statusFilter);
        const paginatedData = this.getPaginatedData(filteredRegions);

        this.renderTable(paginatedData);
        this.updatePagination(filteredRegions.length);
        this.updateStats();
    },

    getFilteredRegions(searchTerm, continentFilter, statusFilter) {
        const allRegionsList = this.createAllRegionsList();

        return allRegionsList.filter(region => {
            const matchesSearch = region.regionCode.toLowerCase().includes(searchTerm) ||
                region.name.toLowerCase().includes(searchTerm);
            const matchesContinent = continentFilter === 'all' || region.continent === continentFilter;
            const matchesStatus = statusFilter === 'all' ||
                (statusFilter === 'open' && region.isOpen) ||
                (statusFilter === 'closed' && !region.isOpen);

            return matchesSearch && matchesContinent && matchesStatus;
        });
    },

    createAllRegionsList() {
        const allRegionsList = [];

        // 首先按照后端返回的顺序添加开放区域（已经按 lastNotifyTime 倒序）
        STATE.openRegions.forEach(region => {
            const regionCode = region.region;
            if (REGION_COORDINATES[regionCode]) {
                allRegionsList.push({
                    regionCode,
                    name: STATE.regionMap[regionCode] || regionCode,
                    isOpen: region.openCount > 0,
                    architectureType: region.architectureType,
                    openTime: region.openTime,
                    openCount: region.openCount,
                    monthlyOpenCount: region.monthlyOpenCount || 0,
                    lastNotifyTime: region.lastNotifyTime,
                    continent: utils.getContinent(regionCode),
                    sortOrder: allRegionsList.length // 保持原始顺序
                });
            }
        });

        // 然后添加未开放区域（按 regionCode 排序）
        const addedRegions = new Set(allRegionsList.map(r => r.regionCode));
        const unopenedRegions = [];

        for (const regionCode in REGION_COORDINATES) {
            if (!addedRegions.has(regionCode)) {
                unopenedRegions.push({
                    regionCode,
                    name: STATE.regionMap[regionCode] || regionCode,
                    isOpen: false,
                    architectureType: '--',
                    openTime: null,
                    openCount: 0,
                    monthlyOpenCount: 0,
                    lastNotifyTime: null,
                    continent: utils.getContinent(regionCode),
                    sortOrder: 9999 // 未开放的排在后面
                });
            }
        }

        // 未开放区域按 regionCode 排序
        unopenedRegions.sort((a, b) => a.regionCode.localeCompare(b.regionCode));

        // 合并：已开放区域（保持后端顺序）+ 未开放区域（按代码排序）
        return [...allRegionsList, ...unopenedRegions];
    },

    getPaginatedData(filteredRegions) {
        const start = (STATE.currentPage - 1) * CONFIG.pageSize;
        const end = Math.min(start + CONFIG.pageSize, filteredRegions.length);
        return filteredRegions.slice(start, end);
    },

    renderTable(data) {
        const tbody = document.getElementById('arm-regions-tbody');
        if (!tbody) return;

        tbody.innerHTML = '';

        if (data.length === 0) {
            tbody.innerHTML = '<tr><td colspan="8" style="text-align: center;">没有找到匹配的区域</td></tr>';
            return;
        }

        data.forEach(region => {
            const tr = document.createElement('tr');
            tr.innerHTML = '<td>' + utils.createStatusBadge(region.isOpen) + '</td>' +
                '<td>' + region.regionCode + '</td>' +
                '<td>' + region.name + '</td>' +
                '<td>' + region.architectureType + '</td>' +
                '<td>' + utils.formatDateTime(region.openTime) + '</td>' +
                '<td>' + region.openCount + '</td>' +
                '<td>' + (region.monthlyOpenCount || 0) + '</td>' +
                '<td>' + utils.formatDateTime(region.lastNotifyTime) + '</td>';
            tbody.appendChild(tr);
        });
    },

    updatePagination(totalItems) {
        const totalPages = Math.ceil(totalItems / CONFIG.pageSize);
        const pagination = document.getElementById('regions-pagination');
        if (!pagination) return;

        pagination.innerHTML = '';

        if (totalPages <= 1) return;

        this.createPaginationButtons(pagination, totalPages);
    },

    createPaginationButtons(pagination, totalPages) {
        // Previous button
        const prevButton = document.createElement('button');
        prevButton.innerHTML = '&laquo;';
        prevButton.disabled = STATE.currentPage === 1;
        prevButton.addEventListener('click', () => this.changePage(STATE.currentPage - 1));
        pagination.appendChild(prevButton);

        // Page numbers
        let startPage = Math.max(1, STATE.currentPage - Math.floor(CONFIG.maxPaginationPages / 2));
        let endPage = Math.min(totalPages, startPage + CONFIG.maxPaginationPages - 1);

        if (endPage - startPage + 1 < CONFIG.maxPaginationPages) {
            startPage = Math.max(1, endPage - CONFIG.maxPaginationPages + 1);
        }

        for (let i = startPage; i <= endPage; i++) {
            const pageButton = document.createElement('button');
            pageButton.textContent = i;
            pageButton.className = i === STATE.currentPage ? 'active' : '';
            pageButton.addEventListener('click', () => this.changePage(i));
            pagination.appendChild(pageButton);
        }

        // Next button
        const nextButton = document.createElement('button');
        nextButton.innerHTML = '&raquo;';
        nextButton.disabled = STATE.currentPage === totalPages;
        nextButton.addEventListener('click', () => this.changePage(STATE.currentPage + 1));
        pagination.appendChild(nextButton);
    },

    changePage(newPage) {
        STATE.currentPage = newPage;
        this.updateTable();
    },

    updateStats() {
        const totalRegions = Object.keys(REGION_COORDINATES).length;
        const openRegionsCount = STATE.openRegions.filter(r => r.openCount > 0).length;

        const totalRegionsEl = document.getElementById('total-regions');
        const openArmRegionsEl = document.getElementById('open-arm-regions');
        const mapArmCountEl = document.getElementById('map-arm-count');

        if (totalRegionsEl) totalRegionsEl.textContent = totalRegions;
        if (openArmRegionsEl) openArmRegionsEl.textContent = openRegionsCount;
        if (mapArmCountEl) mapArmCountEl.textContent = openRegionsCount;

        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayNewRegions = STATE.openRegions.filter(region => {
            if (!region.openTime) return false;
            const openTime = new Date(region.openTime);
            return openTime >= today && region.openCount > 0;
        }).length;

        const todayNewRegionsEl = document.getElementById('today-new-regions');
        if (todayNewRegionsEl) todayNewRegionsEl.textContent = todayNewRegions;
    }
};

// Data Management - 完全使用AJAX
const dataManager = {
    // 初始化时获取所有数据
    async initializeData() {
        try {
            await this.fetchInitialData();
            await this.fetchMyRegions();

            // 更新地图和表格
            if (STATE.mapInitialized) {
                mapManager.updateMarkers(STATE.openRegions);
            }
            tableManager.updateTable();
            this.updateLastUpdateTime();
        } catch (error) {
            console.error('初始化数据失败:', error);
        }
    },

    // 获取ARM区域数据和regionMap
    async fetchInitialData() {
        try {
            const response = await fetch('/resource/arm-data');
            const apiResponse = await response.json();

            if (apiResponse.success && apiResponse.data) {
                const data = apiResponse.data;
                STATE.openRegions = data.armRecords || [];
                STATE.regionMap = data.regionMap || {};
            } else {
                console.error('API返回错误:', apiResponse.message);
                // 如果API失败，使用空数据
                STATE.openRegions = [];
                STATE.regionMap = {};
            }
        } catch (error) {
            console.error('获取ARM数据失败:', error);
            // 如果API不存在，尝试使用原来的端点
            await this.fetchOpenRegions();
        }
    },

    // 获取我的区域数据
    async fetchMyRegions() {
        try {
            const response = await fetch('/resource/my-regions');
            const apiResponse = await response.json();

            if (apiResponse.success && apiResponse.data) {
                STATE.myRegions = apiResponse.data.hasRecords || [];
            } else {
                console.error('获取我的区域API返回错误:', apiResponse.message);
                STATE.myRegions = [];
            }
        } catch (error) {
            console.error('获取我的区域数据失败:', error);
            STATE.myRegions = [];
        }
    },

    // 刷新ARM区域数据
    async fetchOpenRegions() {
        try {
            const response = await fetch('/resource/list');
            const data = await response.json();

            console.log('AJAX获取的数据:', data);
            if (data && data.armRecords) {
                STATE.openRegions = Array.isArray(data.armRecords) ? data.armRecords : [data.armRecords];
            } else if (Array.isArray(data)) {
                STATE.openRegions = data;
            } else if (data && typeof data === 'object') {
                STATE.openRegions = [data];
            }

            if (STATE.mapInitialized) mapManager.updateMarkers(STATE.openRegions);
            tableManager.updateTable();
            this.updateLastUpdateTime();
        } catch (error) {
            console.error('获取开放区域数据失败:', error);
        }
    },

    updateLastUpdateTime() {
        const now = new Date();
        const lastUpdateEl = document.querySelector('#last-update span');
        if (lastUpdateEl) {
            lastUpdateEl.textContent = now.toLocaleString('zh-CN');
        }
    }
};

// Event Handlers
const eventHandlers = {
    setup() {
        // 设置搜索和筛选事件
        const regionSearch = document.getElementById('region-search');
        const continentFilter = document.getElementById('continent-filter');
        const statusFilter = document.getElementById('status-filter');

        if (regionSearch) regionSearch.addEventListener('input', () => tableManager.updateTable());

        // 切换按钮事件
        const btnArmRegions = document.getElementById('btn-arm-regions');
        const btnMyRegions = document.getElementById('btn-my-regions');

        if (btnArmRegions) {
            btnArmRegions.addEventListener('click', () => {
                this.switchView('arm');
            });
        }

        if (btnMyRegions) {
            btnMyRegions.addEventListener('click', () => {
                this.switchView('my');
            });
        }

        // 设置侧边栏展开/收起
        this.setupNavigation();

        // 设置定时刷新
        setInterval(() => {
            dataManager.fetchOpenRegions();
        }, CONFIG.refreshInterval);
    },

    setupNavigation() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            if (parentLink) {
                parentLink.addEventListener('click', (e) => {
                    e.preventDefault();
                    parent.classList.toggle('expanded');
                });
            }
        });

        const activeLink = document.querySelector('.nav-link.active');

        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    },

    switchView(view) {
        if (STATE.currentView === view) return;

        STATE.currentView = view;

        // 更新按钮状态
        document.querySelectorAll('.toggle-btn').forEach(btn => {
            btn.classList.remove('active');
        });

        if (view === 'arm') {
            const btnArm = document.getElementById('btn-arm-regions');
            if (btnArm) btnArm.classList.add('active');
            if (STATE.mapInitialized) mapManager.updateMarkers(STATE.openRegions);
        } else {
            const btnMy = document.getElementById('btn-my-regions');
            if (btnMy) btnMy.classList.add('active');
            if (STATE.mapInitialized) mapManager.updateMarkers(STATE.myRegions);
        }
    }
};

// 页面加载完成后初始化（地图懒加载，默认不初始化）
document.addEventListener('DOMContentLoaded', async () => {
    await dataManager.initializeData();
    eventHandlers.setup();
    // Close filter dropdowns on outside click
    document.addEventListener('click', function() {
        document.querySelectorAll('.filter-dropdown-panel').forEach(function(p) {
            p.style.display = 'none';
        });
        document.querySelectorAll('.filter-dropdown-btn').forEach(function(b) {
            b.classList.remove('open');
        });
    });
});

function toggleMapVisibility() {
    const wrapper = document.getElementById('world-map-wrapper');
    const btn = document.getElementById('toggleMapBtn');
    const icon = document.getElementById('toggleMapIcon');
    const text = document.getElementById('toggleMapText');
    const isVisible = wrapper.style.display !== 'none';

    if (isVisible) {
        wrapper.style.display = 'none';
        btn.classList.remove('active');
        icon.className = 'fas fa-map';
        text.textContent = text.getAttribute('data-show') || '显示地图';
    } else {
        wrapper.style.display = 'block';
        btn.classList.add('active');
        icon.className = 'fas fa-map-marked-alt';
        text.textContent = text.getAttribute('data-hide') || '隐藏地图';
        if (!STATE.mapInitialized) {
            STATE.mapInitialized = true;
            mapManager.initMap();
            if (STATE.currentView === 'my') {
                mapManager.updateMarkers(STATE.myRegions);
            } else {
                mapManager.updateMarkers(STATE.openRegions);
            }
        } else {
            STATE.map.invalidateSize();
        }
    }
}

function toggleFilterDropdown(filterId, event) {
    event.stopPropagation();
    const panel = document.getElementById(filterId + '-panel');
    const btn = document.getElementById(filterId + '-btn');
    const allPanels = document.querySelectorAll('.filter-dropdown-panel');
    const allBtns = document.querySelectorAll('.filter-dropdown-btn');
    const isOpen = panel.style.display !== 'none';
    allPanels.forEach(function(p) { p.style.display = 'none'; });
    allBtns.forEach(function(b) { b.classList.remove('open'); });
    if (!isOpen) {
        panel.style.display = 'block';
        if (btn) btn.classList.add('open');
    }
}

function selectFilterOption(filterId, value, el) {
    // Update hidden select
    const select = document.getElementById(filterId);
    if (select) select.value = value;
    // Update label
    const label = document.getElementById(filterId + '-label');
    if (label) label.textContent = el.textContent.trim();
    // Update active class
    const panel = document.getElementById(filterId + '-panel');
    if (panel) panel.querySelectorAll('.filter-option').forEach(function(o) { o.classList.remove('active'); });
    el.classList.add('active');
    // Close panel
    if (panel) panel.style.display = 'none';
    const btn = document.getElementById(filterId + '-btn');
    if (btn) btn.classList.remove('open');
    // Trigger table update
    tableManager.updateTable();
}