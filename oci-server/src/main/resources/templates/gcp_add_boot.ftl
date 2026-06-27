<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 添加GCP实例</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/app/gcp_add_boot.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--main-bg); }
    </style>
</head>
<body>

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="form-card">
            <div class="form-header">
                <h1 class="form-title">添加GCP实例</h1>
            </div>

            <form action="/other/instances/save" method="post" id="gcpBootForm">
                <input type="hidden" name="tenantId" value="${tenantId?c}">

                <!-- 区域和可用区选择 -->
                <div class="form-section">
                    <h3 class="section-title">
                        <i class="fas fa-globe"></i>
                        区域和可用区
                    </h3>

                    <div class="form-row">
                        <div class="form-group">
                            <label class="form-label" for="region">区域</label>
                            <select class="form-control" id="region" name="region"
                                    data-custom-select data-placeholder="请选择区域" required>
                            </select>
                            <div class="help-text">选择实例所在的地理区域</div>
                        </div>

                        <div class="form-group">
                            <label class="form-label" for="zone">可用区</label>
                            <select class="form-control" id="zone" name="zone"
                                    data-custom-select data-placeholder="请先选择区域" required>
                            </select>
                            <div class="help-text">选择具体的可用区</div>
                        </div>
                    </div>
                </div>

                <!-- 机器类型选择 -->
                <div class="form-section">
                    <h3 class="section-title">
                        <i class="fas fa-server"></i>
                        机器类型
                    </h3>

                    <div class="machine-type-selection">
                        <div class="machine-type-tabs">
                            <div class="machine-type-tab active" data-tab="predefined">预定义类型</div>
                            <div class="machine-type-tab" data-tab="custom">自定义配置</div>
                        </div>

                        <!-- 预定义机器类型 -->
                        <div class="tab-content active" id="predefined-tab">
                            <!-- 共享核心系列 -->
                            <h4 class="machine-type-category">
                                <i class="fas fa-share-alt"></i>
                                共享核心 - 经济型
                            </h4>
                            <div class="machine-type-grid" id="sharedCoreTypes">
                                <!-- 动态生成 -->
                            </div>

                            <!-- 标准系列 -->
                            <h4 class="machine-type-category">
                                <i class="fas fa-desktop"></i>
                                通用型
                            </h4>
                            <div class="machine-type-grid" id="standardTypes">
                                <!-- 动态生成 -->
                            </div>

                            <!-- 高内存系列 -->
                            <h4 class="machine-type-category">
                                <i class="fas fa-memory"></i>
                                高内存型
                            </h4>
                            <div class="machine-type-grid" id="highMemTypes">
                                <!-- 动态生成 -->
                            </div>

                            <!-- 高CPU系列 -->
                            <h4 class="machine-type-category">
                                <i class="fas fa-microchip"></i>
                                高CPU型
                            </h4>
                            <div class="machine-type-grid" id="highCpuTypes">
                                <!-- 动态生成 -->
                            </div>

                            <!-- 计算优化型 -->
                            <h4 class="machine-type-category">
                                <i class="fas fa-rocket"></i>
                                计算优化型
                            </h4>
                            <div class="machine-type-grid" id="computeOptimizedTypes">
                                <!-- 动态生成 -->
                            </div>
                        </div>

                        <!-- 自定义机器类型 -->
                        <div class="tab-content" id="custom-tab">
                            <div class="custom-machine-config">
                                <div class="custom-title">
                                    <i class="fas fa-sliders-h"></i>
                                    自定义CPU和内存配置
                                </div>

                                <div class="custom-row">
                                    <div class="form-group">
                                        <label class="form-label" for="custom-cpu">CPU数量 (vCPU)</label>
                                        <input type="number" class="form-control" id="custom-cpu"
                                               min="1" max="96" value="2" step="1">
                                        <div class="help-text">CPU数量必须是1或偶数，范围：1-96</div>
                                    </div>

                                    <div class="form-group">
                                        <label class="form-label" for="custom-memory">内存大小 (GB)</label>
                                        <input type="number" class="form-control" id="custom-memory"
                                               min="1" max="624" value="4">
                                        <div class="help-text">内存大小，整数GB，范围：1-624GB</div>
                                    </div>
                                </div>

                                <div class="custom-preview">
                                    <div class="preview-title">配置预览</div>
                                    <div class="preview-specs" id="custom-preview">
                                        <div>• 机器类型: <span id="custom-machine-type">custom-2-4096</span></div>
                                        <div>• CPU: <span id="preview-cpu">2</span> vCPU</div>
                                        <div>• 内存: <span id="preview-memory">4</span> GB</div>
                                        <div>• 估算价格: 根据使用量计费</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 系统镜像选择 -->
                <div class="form-section">
                    <h3 class="section-title">
                        <i class="fas fa-compact-disc"></i>
                        操作系统
                    </h3>

                    <div class="image-grid" id="imageGrid">
                        <!-- 动态生成 -->
                    </div>
                </div>

                <!-- 实例配置 -->
                <div class="form-section">
                    <h3 class="section-title">
                        <i class="fas fa-cogs"></i>
                        实例配置
                    </h3>

                    <div class="form-row-3">
                        <div class="form-group">
                            <label class="form-label" for="instanceName">实例名称</label>
                            <input type="text" class="form-control" id="instanceName" name="instanceName"
                                   required placeholder="输入实例名称">
                            <div class="help-text">实例的唯一标识名称</div>
                        </div>

                        <div class="form-group">
                            <label class="form-label" for="diskSize">磁盘大小(GB)</label>
                            <input type="number" class="form-control" id="diskSize" name="diskSize"
                                   required min="10" value="20">
                            <div class="help-text">系统盘大小，最小10GB</div>
                        </div>

                        <div class="form-group">
                            <label class="form-label" for="instanceCount">实例数量</label>
                            <input type="number" class="form-control" id="instanceCount" name="instanceCount"
                                   required min="1" max="10" value="1">
                            <div class="help-text">创建实例的数量</div>
                        </div>
                    </div>
                </div>

                <!-- 隐藏字段 -->
                <input type="hidden" id="machineType" name="machineType" value="">
                <input type="hidden" id="sourceImage" name="sourceImage" value="">
                <input type="hidden" id="isCustomMachine" name="isCustomMachine" value="false">
                <input type="hidden" id="customCpuCount" name="customCpuCount" value="">
                <input type="hidden" id="customMemoryMb" name="customMemoryMb" value="">

                <div class="form-actions">
                    <button type="submit" class="btn btn-primary" id="submit-btn">
                        <i class="fas fa-plus"></i>
                        创建GCP实例
                    </button>
                    <a href="/tenants/list" class="btn btn-secondary">
                        <i class="fas fa-times"></i>
                        取消
                    </a>
                </div>
            </form>
        </div>
    </main>
</div>

<script src="/js/sweetalert2.min.js"></script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script>
    // GCP区域数据
    const GCP_REGIONS = {
        'asia-east1': { name: '中国台湾', zones: ['asia-east1-a', 'asia-east1-b', 'asia-east1-c'] },
        'asia-east2': { name: '中国香港', zones: ['asia-east2-a', 'asia-east2-b', 'asia-east2-c'] },
        'asia-northeast1': { name: '东京', zones: ['asia-northeast1-a', 'asia-northeast1-b', 'asia-northeast1-c'] },
        'asia-northeast2': { name: '大阪', zones: ['asia-northeast2-a', 'asia-northeast2-b', 'asia-northeast2-c'] },
        'asia-northeast3': { name: '首尔', zones: ['asia-northeast3-a', 'asia-northeast3-b', 'asia-northeast3-c'] },
        'asia-south1': { name: '孟买', zones: ['asia-south1-a', 'asia-south1-b', 'asia-south1-c'] },
        'asia-south2': { name: '德里', zones: ['asia-south2-a', 'asia-south2-b', 'asia-south2-c'] },
        'asia-southeast1': { name: '新加坡', zones: ['asia-southeast1-a', 'asia-southeast1-b', 'asia-southeast1-c'] },
        'asia-southeast2': { name: '雅加达', zones: ['asia-southeast2-a', 'asia-southeast2-b', 'asia-southeast2-c'] },
        'australia-southeast1': { name: '悉尼', zones: ['australia-southeast1-a', 'australia-southeast1-b', 'australia-southeast1-c'] },
        'australia-southeast2': { name: '墨尔本', zones: ['australia-southeast2-a', 'australia-southeast2-b', 'australia-southeast2-c'] },
        'europe-central2': { name: '华沙', zones: ['europe-central2-a', 'europe-central2-b', 'europe-central2-c'] },
        'europe-north1': { name: '芬兰', zones: ['europe-north1-a', 'europe-north1-b', 'europe-north1-c'] },
        'europe-west1': { name: '比利时', zones: ['europe-west1-b', 'europe-west1-c', 'europe-west1-d'] },
        'europe-west2': { name: '伦敦', zones: ['europe-west2-a', 'europe-west2-b', 'europe-west2-c'] },
        'europe-west3': { name: '法兰克福', zones: ['europe-west3-a', 'europe-west3-b', 'europe-west3-c'] },
        'europe-west4': { name: '荷兰', zones: ['europe-west4-a', 'europe-west4-b', 'europe-west4-c'] },
        'europe-west6': { name: '苏黎世', zones: ['europe-west6-a', 'europe-west6-b', 'europe-west6-c'] },
        'europe-west8': { name: '米兰', zones: ['europe-west8-a', 'europe-west8-b', 'europe-west8-c'] },
        'europe-west9': { name: '巴黎', zones: ['europe-west9-a', 'europe-west9-b', 'europe-west9-c'] },
        'us-central1': { name: '爱荷华', zones: ['us-central1-a', 'us-central1-b', 'us-central1-c', 'us-central1-f'] },
        'us-east1': { name: '南卡罗来纳', zones: ['us-east1-b', 'us-east1-c', 'us-east1-d'] },
        'us-east4': { name: '北弗吉尼亚', zones: ['us-east4-a', 'us-east4-b', 'us-east4-c'] },
        'us-west1': { name: '俄勒冈', zones: ['us-west1-a', 'us-west1-b', 'us-west1-c'] },
        'us-west2': { name: '洛杉矶', zones: ['us-west2-a', 'us-west2-b', 'us-west2-c'] },
        'us-west3': { name: '盐湖城', zones: ['us-west3-a', 'us-west3-b', 'us-west3-c'] },
        'us-west4': { name: '拉斯维加斯', zones: ['us-west4-a', 'us-west4-b', 'us-west4-c'] }
    };

    // GCP机器类型数据
    const GCP_MACHINE_TYPES = {
        sharedCore: [
            { name: 'e2-micro', displayName: '共享核心 - 微型', vCpu: 0.25, memory: 1, category: 'shared-core' },
            { name: 'e2-small', displayName: '共享核心 - 小型', vCpu: 0.5, memory: 2, category: 'shared-core' },
            { name: 'e2-medium', displayName: '共享核心 - 中型', vCpu: 1, memory: 4, category: 'shared-core' }
        ],
        standard: [
            { name: 'e2-standard-2', displayName: '经济型 - 2核', vCpu: 2, memory: 8, category: 'standard' },
            { name: 'e2-standard-4', displayName: '经济型 - 4核', vCpu: 4, memory: 16, category: 'standard' },
            { name: 'n1-standard-1', displayName: '通用型 - 1核', vCpu: 1, memory: 3.75, category: 'standard' },
            { name: 'n1-standard-2', displayName: '通用型 - 2核', vCpu: 2, memory: 7.5, category: 'standard' },
            { name: 'n1-standard-4', displayName: '通用型 - 4核', vCpu: 4, memory: 15, category: 'standard' },
            { name: 'n2-standard-2', displayName: '第二代通用型 - 2核', vCpu: 2, memory: 8, category: 'standard' },
            { name: 'n2-standard-4', displayName: '第二代通用型 - 4核', vCpu: 4, memory: 16, category: 'standard' }
        ],
        highMem: [
            { name: 'e2-highmem-2', displayName: '经济型高内存 - 2核', vCpu: 2, memory: 16, category: 'highmem' },
            { name: 'e2-highmem-4', displayName: '经济型高内存 - 4核', vCpu: 4, memory: 32, category: 'highmem' },
            { name: 'n1-highmem-2', displayName: '高内存型 - 2核', vCpu: 2, memory: 13, category: 'highmem' },
            { name: 'n1-highmem-4', displayName: '高内存型 - 4核', vCpu: 4, memory: 26, category: 'highmem' }
        ],
        highCpu: [
            { name: 'e2-highcpu-2', displayName: '经济型高CPU - 2核', vCpu: 2, memory: 2, category: 'highcpu' },
            { name: 'e2-highcpu-4', displayName: '经济型高CPU - 4核', vCpu: 4, memory: 4, category: 'highcpu' },
            { name: 'n1-highcpu-2', displayName: '高CPU型 - 2核', vCpu: 2, memory: 1.8, category: 'highcpu' },
            { name: 'n1-highcpu-4', displayName: '高CPU型 - 4核', vCpu: 4, memory: 3.6, category: 'highcpu' }
        ],
        computeOptimized: [
            { name: 'c2-standard-4', displayName: '计算优化型 - 4核', vCpu: 4, memory: 16, category: 'compute-optimized' },
            { name: 'c2-standard-8', displayName: '计算优化型 - 8核', vCpu: 8, memory: 32, category: 'compute-optimized' },
            { name: 'c2-standard-16', displayName: '计算优化型 - 16核', vCpu: 16, memory: 64, category: 'compute-optimized' }
        ]
    };

    // GCP镜像数据
    const GCP_IMAGES = [
        {
            name: 'debian-12-bookworm-v20250610',
            displayName: 'Debian 12 (Bookworm)',
            description: 'Debian GNU/Linux 12 (bookworm), amd64',
            architecture: 'X86_64',
            projectId: 'debian-cloud',
            family: 'debian-12'
        },
        {
            name: 'debian-12-bookworm-arm64-v20250610',
            displayName: 'Debian 12 (Bookworm) ARM64',
            description: 'Debian GNU/Linux 12 (bookworm), arm64',
            architecture: 'ARM64',
            projectId: 'debian-cloud',
            family: 'debian-12-arm64'
        },
        {
            name: 'ubuntu-2004-focal-v20250610',
            displayName: 'Ubuntu 20.04 LTS',
            description: 'Ubuntu 20.04.6 LTS, amd64',
            architecture: 'X86_64',
            projectId: 'ubuntu-os-cloud',
            family: 'ubuntu-2004-lts'
        },
        {
            name: 'ubuntu-2204-jammy-v20250610',
            displayName: 'Ubuntu 22.04 LTS',
            description: 'Ubuntu 22.04.4 LTS, amd64',
            architecture: 'X86_64',
            projectId: 'ubuntu-os-cloud',
            family: 'ubuntu-2204-lts'
        }
    ];

    // 全局变量
    let currentMachineType = '';
    let isCustomMachine = false;

    // 初始化页面
    document.addEventListener('DOMContentLoaded', function() {
        initRegionSelection();
        initMachineTypeSelection();
        initCustomMachineConfig();
        initImageSelection();
        initFormValidation();
        initMenuBehavior();
        initTabSwitching();
    });

    // 初始化区域选择
    function initRegionSelection() {
        const regionSelect = document.getElementById('region');
        const zoneSelect = document.getElementById('zone');

        // 填充区域选项
        Object.keys(GCP_REGIONS).forEach(regionId => {
            const region = GCP_REGIONS[regionId];
            const option = document.createElement('option');
            option.value = regionId;
            option.textContent = region.name + ' (' + regionId + ')';
            regionSelect.appendChild(option);
        });

        // 区域变化时更新可用区
        regionSelect.addEventListener('change', function() {
            const selectedRegion = this.value;
            zoneSelect.innerHTML = '';
            if (window.CustomSelect) CustomSelect.refresh(zoneSelect);

            if (selectedRegion && GCP_REGIONS[selectedRegion]) {
                const zones = GCP_REGIONS[selectedRegion].zones;
                zones.forEach(zoneId => {
                    const option = document.createElement('option');
                    option.value = zoneId;
                    option.textContent = zoneId;
                    zoneSelect.appendChild(option);
                });
            }
        });
    }

    // 初始化标签页切换
    function initTabSwitching() {
        const tabs = document.querySelectorAll('.machine-type-tab');
        const tabContents = document.querySelectorAll('.tab-content');

        tabs.forEach(tab => {
            tab.addEventListener('click', function() {
                const targetTab = this.dataset.tab;

                // 切换标签页激活状态
                tabs.forEach(t => t.classList.remove('active'));
                this.classList.add('active');

                // 切换内容区域
                tabContents.forEach(content => {
                    content.classList.remove('active');
                });
                document.getElementById(targetTab + '-tab').classList.add('active');

                // 更新机器类型状态
                if (targetTab === 'custom') {
                    isCustomMachine = true;
                    document.getElementById('isCustomMachine').value = 'true';
                    updateCustomMachineType();
                    clearPredefinedSelection();
                } else {
                    isCustomMachine = false;
                    document.getElementById('isCustomMachine').value = 'false';
                    clearCustomSelection();
                }
            });
        });
    }

    // 初始化机器类型选择
    function initMachineTypeSelection() {
        // 渲染各类机器类型
        renderMachineTypes('sharedCoreTypes', GCP_MACHINE_TYPES.sharedCore);
        renderMachineTypes('standardTypes', GCP_MACHINE_TYPES.standard);
        renderMachineTypes('highMemTypes', GCP_MACHINE_TYPES.highMem);
        renderMachineTypes('highCpuTypes', GCP_MACHINE_TYPES.highCpu);
        renderMachineTypes('computeOptimizedTypes', GCP_MACHINE_TYPES.computeOptimized);
    }

    // 渲染机器类型卡片
    function renderMachineTypes(containerId, machineTypes) {
        const container = document.getElementById(containerId);

        machineTypes.forEach(type => {
            const card = document.createElement('div');
            card.className = 'machine-type-card';
            card.dataset.machineType = type.name;

            card.innerHTML =
                '<div class="machine-type-title">' + type.displayName + '</div>' +
                '<div class="machine-type-specs">' +
                '<div>• ' + type.vCpu + ' vCPU</div>' +
                '<div>• ' + type.memory + ' GB 内存</div>' +
                '<div>• 机器类型: ' + type.name + '</div>' +
                '<div class="category-tag ' + type.category + '">' + getCategoryDisplayName(type.category) + '</div>' +
                '</div>';

            card.addEventListener('click', function() {
                if (isCustomMachine) return; // 自定义模式下不允许选择预定义类型

                // 移除其他卡片的选中状态
                document.querySelectorAll('.machine-type-card').forEach(c => c.classList.remove('selected'));
                // 添加选中状态
                this.classList.add('selected');
                // 设置机器类型
                currentMachineType = type.name;
                document.getElementById('machineType').value = type.name;
            });

            container.appendChild(card);
        });
    }

    // 获取类别显示名称
    function getCategoryDisplayName(category) {
        const categoryNames = {
            'shared-core': '共享核心',
            'standard': '标准',
            'highmem': '高内存',
            'highcpu': '高CPU',
            'compute-optimized': '计算优化'
        };
        return categoryNames[category] || category;
    }

    // 初始化自定义机器配置
    function initCustomMachineConfig() {
        const cpuInput = document.getElementById('custom-cpu');
        const memoryInput = document.getElementById('custom-memory');

        // CPU输入框事件
        cpuInput.addEventListener('input', function() {
            let cpuCount = parseInt(this.value);

            // 验证范围
            if (cpuCount < 1) cpuCount = 1;
            if (cpuCount > 96) cpuCount = 96;

            // 确保CPU数量规则：1或偶数
            if (cpuCount > 1 && cpuCount % 2 !== 0) {
                cpuCount = cpuCount + 1;
                if (cpuCount > 96) cpuCount = cpuCount - 2;
            }

            this.value = cpuCount;

            // 更新内存范围限制
            updateMemoryRange(cpuCount);
            updateCustomMachineType();
        });

        // 内存输入框事件
        memoryInput.addEventListener('input', function() {
            let memoryGb = parseInt(this.value);

            // 验证范围
            if (memoryGb < 1) memoryGb = 1;
            if (memoryGb > 624) memoryGb = 624;

            this.value = memoryGb;

            updateCustomMachineType();
        });

        // 初始化内存范围
        updateMemoryRange(2);
    }

    // - 确保设置整数min/max
    function updateMemoryRange(cpuCount) {
        const memoryInput = document.getElementById('custom-memory');

        // 计算范围并向上/向下取整，确保是整数
        const minMemory = Math.max(Math.ceil(0.9 * cpuCount), 1); // 向上取整
        const maxMemory = Math.min(Math.floor(6.5 * cpuCount), 624); // 向下取整

        // 设置整数的min和max属性
        memoryInput.min = minMemory;
        memoryInput.max = maxMemory;

        // 如果当前内存值超出范围，调整到范围内
        const currentMemory = parseInt(memoryInput.value);
        if (currentMemory < minMemory) {
            memoryInput.value = minMemory;
        } else if (currentMemory > maxMemory) {
            memoryInput.value = maxMemory;
        }

        // 更新帮助文本
        const helpText = memoryInput.parentElement.querySelector('.help-text');
        helpText.textContent = `内存大小，整数GB，当前CPU范围：`+ minMemory+`-`+ maxMemory+`GB`;
    }

    // 更新自定义机器类型
    function updateCustomMachineType() {
        if (!isCustomMachine) return;

        const cpuCount = parseInt(document.getElementById('custom-cpu').value);
        const memoryGb = parseInt(document.getElementById('custom-memory').value);
        const memoryMb = memoryGb * 1024; // 转换为MB

        const customMachineType = 'custom-' + cpuCount + '-' + memoryMb;

        // 更新显示
        document.getElementById('custom-machine-type').textContent = customMachineType;
        document.getElementById('preview-cpu').textContent = cpuCount;
        document.getElementById('preview-memory').textContent = memoryGb;

        // 设置隐藏字段
        currentMachineType = customMachineType;
        document.getElementById('machineType').value = customMachineType;
        document.getElementById('customCpuCount').value = cpuCount;
        document.getElementById('customMemoryMb').value = memoryMb;
    }

    // 清除预定义选择
    function clearPredefinedSelection() {
        document.querySelectorAll('.machine-type-card').forEach(card => {
            card.classList.remove('selected');
        });
    }

    // 清除自定义选择
    function clearCustomSelection() {
        // 重置输入框到默认值
        document.getElementById('custom-cpu').value = 2;
        document.getElementById('custom-memory').value = 4;
        updateMemoryRange(2);

        // 清除隐藏字段
        document.getElementById('customCpuCount').value = '';
        document.getElementById('customMemoryMb').value = '';
    }

    // 初始化镜像选择
    function initImageSelection() {
        const imageGrid = document.getElementById('imageGrid');

        GCP_IMAGES.forEach(image => {
            const card = document.createElement('div');
            card.className = 'image-card';
            card.dataset.imageName = image.name;

            card.innerHTML =
                '<div class="image-title">' + image.displayName + '</div>' +
                '<div class="image-specs">' +
                '<div>• ' + image.description + '</div>' +
                '<div>• 项目: ' + image.projectId + '</div>' +
                '<div>• 镜像族: ' + image.family + '</div>' +
                '<div class="arch-tag ' + image.architecture.toLowerCase() + '">' + image.architecture + '</div>' +
                '</div>';

            card.addEventListener('click', function() {
                // 移除其他卡片的选中状态
                document.querySelectorAll('.image-card').forEach(c => c.classList.remove('selected'));
                // 添加选中状态
                this.classList.add('selected');
                // 设置隐藏字段
                const sourceImageUrl = 'projects/' + image.projectId + '/global/images/' + image.name;
                document.getElementById('sourceImage').value = sourceImageUrl;
            });

            imageGrid.appendChild(card);
        });

        // 默认选择第一个镜像
        if (GCP_IMAGES.length > 0) {
            const firstCard = imageGrid.querySelector('.image-card');
            if (firstCard) {
                firstCard.click();
            }
        }
    }

    // 表单验证 - 全部使用SweetAlert2
    function initFormValidation() {
        const form = document.getElementById('gcpBootForm');

        form.addEventListener('submit', function(e) {
            e.preventDefault();

            // 验证区域和可用区
            const region = document.getElementById('region').value;
            const zone = document.getElementById('zone').value;
            if (!region || !zone) {
                Swal.fire({
                    icon: 'warning',
                    title: '请选择区域',
                    text: '请选择区域和可用区',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证机器类型
            if (!currentMachineType) {
                Swal.fire({
                    icon: 'warning',
                    title: '请选择机器类型',
                    text: '请选择机器类型或配置自定义规格',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证自定义机器类型的CPU和内存限制
            let cpuCount, memoryGb; // 在这里声明变量
            if (isCustomMachine) {
                cpuCount = parseInt(document.getElementById('custom-cpu').value);
                memoryGb = parseInt(document.getElementById('custom-memory').value);

                // 验证CPU规则
                if (cpuCount < 1 || cpuCount > 96) {
                    Swal.fire({
                        icon: 'error',
                        title: 'CPU配置错误',
                        text: 'CPU数量必须在1-96之间',
                        confirmButtonColor: '#1abc9c'
                    });
                    return;
                }

                if (cpuCount > 1 && cpuCount % 2 !== 0) {
                    Swal.fire({
                        icon: 'error',
                        title: 'CPU配置错误',
                        text: 'CPU数量必须是1或偶数',
                        confirmButtonColor: '#1abc9c'
                    });
                    return;
                }

                // 验证内存规则
                const minMemory = Math.max(Math.ceil(0.9 * cpuCount), 1);
                const maxMemory = Math.floor(6.5 * cpuCount);
                if (memoryGb < minMemory || memoryGb > maxMemory) {
                    Swal.fire({
                        icon: 'error',
                        title: '内存配置错误',
                        text: '内存大小必须在 ' + minMemory + 'GB 到 ' + maxMemory + 'GB 之间',
                        confirmButtonColor: '#1abc9c'
                    });
                    return;
                }
            }

            // 验证镜像
            const sourceImage = document.getElementById('sourceImage').value;
            if (!sourceImage) {
                Swal.fire({
                    icon: 'warning',
                    title: '请选择镜像',
                    text: '请选择操作系统镜像',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证实例名称
            const instanceName = document.getElementById('instanceName').value.trim();
            if (!instanceName) {
                Swal.fire({
                    icon: 'warning',
                    title: '请输入实例名称',
                    text: '实例名称不能为空',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证实例名称格式 (GCP要求小写字母、数字和连字符)
            const namePattern = /^[a-z]([-a-z0-9]*[a-z0-9])?$/;
            if (!namePattern.test(instanceName)) {
                Swal.fire({
                    icon: 'error',
                    title: '实例名称格式错误',
                    text: '实例名称只能包含小写字母、数字和连字符，且必须以字母开头',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证磁盘大小
            const diskSize = parseInt(document.getElementById('diskSize').value);
            if (diskSize < 10) {
                Swal.fire({
                    icon: 'error',
                    title: '磁盘大小错误',
                    text: '磁盘大小不能小于10GB',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 验证实例数量
            const instanceCount = parseInt(document.getElementById('instanceCount').value);
            if (instanceCount < 1 || instanceCount > 10) {
                Swal.fire({
                    icon: 'error',
                    title: '实例数量错误',
                    text: '实例数量必须在1-10之间',
                    confirmButtonColor: '#1abc9c'
                });
                return;
            }

            // 显示确认对话框
            const machineConfig = isCustomMachine ?
                cpuCount + '核 ' + memoryGb + 'GB (自定义)' :
                currentMachineType;

            Swal.fire({
                title: '确认创建实例',
                html: '<div style="text-align: left; padding: 10px;">' +
                    '<p><strong>实例名称：</strong>' + instanceName + '</p>' +
                    '<p><strong>区域：</strong>' + zone + '</p>' +
                    '<p><strong>机器配置：</strong>' + machineConfig + '</p>' +
                    '<p><strong>磁盘大小：</strong>' + diskSize + 'GB</p>' +
                    '<p><strong>实例数量：</strong>' + instanceCount + '</p>' +
                    '</div>',
                icon: 'question',
                showCancelButton: true,
                confirmButtonColor: '#1abc9c',
                cancelButtonColor: '#6c757d',
                confirmButtonText: '确认创建',
                cancelButtonText: '取消'
            }).then((result) => {
                if (result.isConfirmed) {
                    // 禁用提交按钮防止重复提交
                    const submitBtn = document.getElementById('submit-btn');
                    submitBtn.disabled = true;
                    submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 创建中...';

                    // 显示创建中的提示
                    showLoading('正在创建实例...');

                    // 提交表单
                    form.submit();
                }
            });
        });
    }

    // 菜单行为
    function initMenuBehavior() {
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

        // 展开当前活动菜单
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    }
</script>
</body>
</html>