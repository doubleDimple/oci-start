<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script>
        (function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();
    </script>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <title>VPS管理系统 - 添加实例</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/loading.js"></script>

    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/app/add_boot.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">

</head>
<body>


<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="form-card">
            <div class="form-header">
                <h1 class="form-title">${msg.get("ins.preOpen")}</h1>
            </div>

            <form action="/tenants/boot/save" method="post" id="bootForm">
                <input type="hidden" name="tenantId" id="tenantIdHidden" value="${tenantId?c}">

                <div class="form-section" style="margin-bottom: 20px; padding: 15px;">
                    <h3 class="section-title" style="margin-bottom: 10px;">
                        <i class="fas fa-globe"></i> 选择区域
                    </h3>
                    <div class="form-group" style="margin-bottom: 0;">
                        <select id="regionSelect" class="form-control" data-custom-select data-placeholder="选择区域..." data-max-width="320px">
                            <option value="">loading...</option>
                        </select>
                    </div>
                </div>

                <div class="mode-tabs">
                    <div class="mode-tab active" data-mode="quick">
                        <i class="fas fa-bolt"></i> ${msg.get("boot.quick")}
                    </div>
                    <div class="mode-tab" data-mode="custom">
                        <i class="fas fa-sliders-h"></i> ${msg.get("boot.defBoot")}
                    </div>
                </div>

                <input type="hidden" name="operatingSystem" id="operatingSystemHidden"/>
                <input type="hidden" name="operatingSystemVersion" id="operatingSystemVersionHidden"/>
                <input type="hidden" name="imageId" id="imageIdHidden"/>

                <input type="hidden" id="ocpu" name="ocpu" value="1">
                <input type="hidden" id="memory" name="memory" value="6">
                <input type="hidden" id="disk" name="disk" value="50">
                <input type="hidden" id="architecture" name="architecture" value="ARM">
                <input type="hidden" id="rootPassword" name="rootPassword" value="">
                <input type="hidden" id="loopTime" name="loopTime" value="60">
                <input type="hidden" id="instanceCountHidden" name="instanceCount" value="1">

                <div id="quick-mode-area" class="mode-area active">
                    <div class="form-section">
                        <h3 class="section-title"><i class="fas fa-rocket"></i> ${msg.get("boot.selectArch")}</h3>
                        <p class="help-text" style="margin-bottom: 15px;">${msg.get("boot.quickContent")}</p>

                        <div class="template-grid quick-grid">
                            <div class="template-card quick-card selected" data-template='{"ocpu": 1, "memory": 6, "disk": 50, "architecture": "ARM", "count": 1}'>
                                <div class="template-title">${msg.get("ins.baseConfigFree")} (ARM)</div>
                                <div class="template-specs">
                                    <div><i class="fas fa-microchip"></i> 1 OCPU / 6 GB MEM</div>
                                    <div><i class="fas fa-hdd"></i> 50 GB DISK</div>
                                </div>
                            </div>
                            <div class="template-card quick-card" data-template='{"ocpu": 1, "memory": 1, "disk": 50, "architecture": "AMD", "count": 1}'>
                                <div class="template-title">${msg.get("ins.amdBaseConfigFree")} (AMD)</div>
                                <div class="template-specs">
                                    <div><i class="fas fa-microchip"></i> 1 OCPU / 1 GB MEM</div>
                                    <div><i class="fas fa-hdd"></i> 50 GB DISK</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="custom-mode-area" class="mode-area" style="display: none;">

                    <div class="form-section">
                        <h3 class="section-title"><i class="fas fa-cubes"></i> ${msg.get("ins.template")}</h3>

                        <h4 class="architecture-title"><i class="fas fa-microchip"></i> ${msg.get("ins.armArch")}</h4>
                        <div class="template-grid">
                            <div class="template-card custom-card" data-template='{"ocpu": 1, "memory": 6, "disk": 50, "maxCount": 100, "architecture": "ARM"}'>
                                <div class="template-title">${msg.get("ins.baseConfigFree")}</div>
                                <div class="template-specs">
                                    <div>• 1 OCPU | 6 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.baseConfigMaxCount")}: 100</div>
                                    <div class="arch-tag">ARM</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 2, "memory": 12, "disk": 50, "maxCount": 100, "architecture": "ARM"}'>
                                <div class="template-title">${msg.get("ins.standardConfigFree")}</div>
                                <div class="template-specs">
                                    <div>• 2 OCPU | 12 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.standardConfigMaxCount")}: 100</div>
                                    <div class="arch-tag">ARM</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 4, "memory": 24, "disk": 50, "maxCount": 100, "architecture": "ARM"}'>
                                <div class="template-title">${msg.get("ins.highConfigFree")}</div>
                                <div class="template-specs">
                                    <div>• 4 OCPU | 24 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.highConfigMaxCount")}: 100</div>
                                    <div class="arch-tag">ARM</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 4, "memory": 24, "disk": 200, "maxCount": 100, "architecture": "ARM_PAID_A2"}'>
                                <div class="template-title">${msg.get("ins.A2ConfigPay")}</div>
                                <div class="template-specs">
                                    <div>• 4 OCPU | 24 GB MEM | 200 GB DISK</div>
                                    <div>• ${msg.get("ins.A2ConfigMaxCount")}: 100</div>
                                    <div class="arch-tag">ARM</div>
                                </div>
                            </div>
                        </div>

                        <h4 class="architecture-title" style="margin-top: 20px;"><i class="fas fa-microchip"></i> ${msg.get("ins.amdArch")}</h4>
                        <div class="template-grid">
                            <div class="template-card custom-card" data-template='{"ocpu": 1, "memory": 1, "disk": 50, "maxCount": 100, "architecture": "AMD"}'>
                                <div class="template-title">${msg.get("ins.amdBaseConfigFree")}</div>
                                <div class="template-specs">
                                    <div>• 1 OCPU | 1 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.amdConfigMaxCount")}: 100</div>
                                    <div class="arch-tag amd">AMD</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 4, "memory": 24, "disk": 50, "maxCount": 100, "architecture": "AMD_PAID_E3"}'>
                                <div class="template-title">${msg.get("ins.amdE3ConfigPay")}</div>
                                <div class="template-specs">
                                    <div>• 4 OCPU | 24 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.amdConfigMaxCount")}: 100</div>
                                    <div class="arch-tag amd">AMD_PAID_E3</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 4, "memory": 24, "disk": 50, "maxCount": 100, "architecture": "AMD_PAID_E4"}'>
                                <div class="template-title">${msg.get("ins.amdE4ConfigPay")}</div>
                                <div class="template-specs">
                                    <div>• 4 OCPU | 24 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("ins.amdConfigMaxCount")}: 100</div>
                                    <div class="arch-tag amd">AMD_PAID_E4</div>
                                </div>
                            </div>
                            <div class="template-card custom-card" data-template='{"ocpu": 4, "memory": 24, "disk": 50, "maxCount": 100, "architecture": "AMD_PAID_E5"}'>
                                <div class="template-title">${msg.get("ins.amdE5ConfigPay")}</div>
                                <div class="template-specs">
                                    <div>• 4 OCPU | 24 GB MEM | 50 GB DISK</div>
                                    <div>• ${msg.get("amdConfigMaxCount")}: 100</div>
                                    <div class="arch-tag amd">AMD_PAID_E5</div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="form-section" id="system-section" style="display:none;">
                        <div class="section-title"><i class="fas fa-desktop"></i> ${msg.get("ins.selectImage")}</div>
                        <div class="form-group">
                            <label class="form-label">${msg.get("ins.osName")}</label>
                            <select id="operatingSystem" class="form-control" data-custom-select data-placeholder="${msg.get('ins.plzOs')}">
                                <option value="">${msg.get("ins.plzOs")}</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${msg.get("ins.osVersion")}</label>
                            <select id="operatingSystemVersion" class="form-control" data-custom-select data-placeholder="${msg.get('ins.plzVersion')}">
                                <option value="">${msg.get("ins.plzVersion")}</option>
                            </select>
                        </div>
                    </div>

                    <div class="form-section">
                        <h3 class="section-title"><i class="fas fa-copy"></i> ${msg.get("ins.deplyConfig")}</h3>
                        <div class="resource-grid">
                            <div class="form-group">
                                <label class="form-label" for="customInstanceCount">${msg.get("ins.number")}</label>
                                <input type="number" class="form-control" id="customInstanceCount" min="1" value="1">
                                <div class="help-text" id="maxInstanceText">${msg.get("ins.plzConfigTemplate")}</div>
                            </div>

                            <div class="form-group">
                                <label class="form-label">${msg.get("ins.timeRange")}</label>
                                <div class="interval-options">
                                    <button type="button" class="interval-btn" data-value="10">10s</button>
                                    <button type="button" class="interval-btn" data-value="30">30s</button>
                                    <button type="button" class="interval-btn selected" data-value="60">60s</button>
                                    <button type="button" class="interval-btn" data-value="200">200s</button>
                                    <button type="button" class="interval-btn" data-value="500">500s</button>
                                </div>
                                <input type="number" class="form-control" id="customInterval" placeholder="${msg.get("ins.defTimeRange")}" style="width: 120px; margin-top: 10px;">
                            </div>
                        </div>

                        <div class="form-group" style="margin-top: 15px;">
                            <label class="form-label">${msg.get("ins.timeBetween")}:</label>
                            <input type="text" class="form-control" id="dayGap" name="dayGap" placeholder="${msg.get("ins.fomrExample")}" />
                            <div class="help-text">${msg.get("ins.timeBetweenRule1")}<br>${msg.get("ins.timeBetweenRule2")}</div>
                        </div>
                    </div>
                </div>

                <div class="form-actions">
                    <button type="submit" class="btn btn-primary" id="submit-btn">
                        <i class="fas fa-plus"></i> ${msg.get("ins.create")}
                    </button>
                    <a href="/tenants/list" class="btn btn-secondary">
                        <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                    </a>
                </div>
            </form>
        </div>
    </main>
</div>
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_portRange: "${msg.get('common.portRange')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        ins_timeBetweenError: "${msg.get('ins.timeBetweenError')?js_string}",
        ins_timeBetweenRule1: "${msg.get('ins.timeBetweenRule1')?js_string}",
        ins_timeBetweenErrorAnd24Hours: "${msg.get('ins.timeBetweenErrorAnd24Hours')?js_string}",
        ins_timeBetweenErrorDays: "${msg.get('ins.timeBetweenErrorDays')?js_string}",
        ins_plzConfigTemplate: "${msg.get('ins.plzConfigTemplate')?js_string}",
        ins_numError: "${msg.get('ins.numError')?js_string}",
        ins_plzEffectTime: "${msg.get('ins.plzEffectTime')?js_string}",
        ins_plzOs: "${msg.get('ins.plzOs')?js_string}",
        ins_plzVersion: "${msg.get('ins.plzVersion')?js_string}",
        vpn_edit: "${msg.get('vpn.edit')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/add_boot.js"></script>
</body>
</html>