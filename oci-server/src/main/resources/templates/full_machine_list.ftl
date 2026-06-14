<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 抢机实例列表</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/app/full_machine_list.css">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <link rel="stylesheet" href="/css/app/boot_log_drawer.css">
    <script src="/js/common/dropdown-menu.js"></script>
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--main-bg); }
    </style>
    <#include "common/pagination.ftl" />

</head>
<body>
<#--
<#include "common/version_info.ftl">
-->


<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->


    <main class="main-content">
        <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-microchip"></i>
                <span>${msg.get("openBoot.list")}</span>
            </h1>
            <div class="view-actions">

                <!-- 级联下拉搜索框 -->
                <div class="filter-controls" style="padding: 15px;">
                    <div class="filter-item">
                        <label class="filter-label">${msg.get("openBoot.select")}：</label>
                        <div class="cascade-container">
                            <div class="cascade-selects">
                                <select id="tenantSelect" class="cascade-select"
                                        data-custom-select data-searchable data-page-size="5"
                                        data-placeholder="${msg.get("openBoot.selectTenant")}"
                                        onchange="loadRegions()">
                                </select>
                                <select id="regionSelect" class="cascade-select"
                                        data-custom-select data-searchable data-page-size="5"
                                        data-placeholder="${msg.get("openBoot.selectRegion")}"
                                        onchange="regionChanged()" disabled>
                                </select>
                            </div>
                            <button id="goToInstanceBtn" class="btn btn-primary" onclick="goToInstances()" disabled>
                                <i class="fas fa-search"></i> ${msg.get("openBoot.search")}
                            </button>
                        </div>
                    </div>
                </div>

                <div class="view-toggle">
                    <button class="btn" id="spoilerToggleBtn" title="${msg.get('tenant.toggleName')}">
                        <i class="fas fa-eye" id="spoilerToggleIcon"></i>
                    </button>
                </div>
                <div class="btn-group">
                    <button class="btn btn-primary" onclick="handleBatchStart()">
                        <i class="fas fa-play-circle"></i>
                        <span>${msg.get("openBoot.open")}</span>
                    </button>
                    <button class="btn btn-warning" onclick="handleBatchStop()">
                        <i class="fas fa-stop-circle"></i>
                        <span>${msg.get("openBoot.stop")}</span>
                    </button>
                    <button class="btn btn-warning" onclick="handleBatchFail()">
                        <i class="fas fa-stop-circle"></i>
                        <span>${msg.get("openBoot.reset")}</span>
                    </button>
                    <a href="/tenants/list" class="btn btn-primary">
                        <i class="fas fa-arrow-left"></i>
                        <span>${msg.get("common.rollback")}</span>
                    </a>
                </div>
            </div>
        </div>

        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>${msg.get("index.donation.tableNo")}</th>
                    <th>${msg.get("openBoot.tenantName")}</th>
                    <th>${msg.get("openBoot.remark")}</th>
                    <th>${msg.get("openBoot.regionCode")}</th>
                    <th>${msg.get("openBoot.taskStatus")}</th>
                    <th>${msg.get("openBoot.taskTotal")}</th>
                    <th>${msg.get("openBoot.handIng")}</th>
                    <th>${msg.get("openBoot.openTotal")}</th>
                    <th>${msg.get("openBoot.yesterdayCount")}</th>
                    <th>${msg.get("openBoot.todayCount")}</th>
                    <th>${msg.get("openBoot.failCount")}</th>
                    <th>${msg.get("openBoot.successCount")}</th>
                    <#--<th>预开数量</th>-->
                    <th>${msg.get("openBoot.architecture")}</th>
                    <th>${msg.get("tenant.createTime")!'创建时间'}</th>
                    <th>${msg.get("openBoot.action")}</th>
                </tr>
                </thead>
                <tbody>
                <#list bootInstances as bootInstance>
                    <tr>
                        <td>${bootInstance_index + 1}</td>
                        <td>
                            <#assign tn = (bootInstance.tenancyName?has_content)?then(bootInstance.tenancyName, (bootInstance.defName)!'')>
                            <#assign maskedTn = (tn?length > 2)?then(tn?substring(0,1) + '***' + tn?substring(tn?length - 1), (tn?length > 0)?then('***', ''))>
                            <span class="name-spoiler is-hidden" title="${tn}">
                                <span class="name-masked">${maskedTn}</span>
                                <span class="name-full">${tn}</span>
                            </span>
                        </td>
                        <td><span class="truncate" data-fulltext="${bootInstance.defName!''}">${bootInstance.defName!''}</span></td>
                        <td><span class="truncate" data-fulltext="${bootInstance.regionName}">${bootInstance.regionName}</span></td>
                        <td>
                            <span class="truncate status-badge ${bootInstance.openBootFlag?then('status-running', 'status-idle')}"
                                  data-fulltext="${bootInstance.openBootFlag?then('${msg.get("openBoot.task")}', '${msg.get("openBoot.noTask")}')}">
                                ${bootInstance.openBootFlag?then('${msg.get("openBoot.task")}', '${msg.get("openBoot.noTask")}')}
                            </span>
                        </td>
                        <td><span class="truncate" data-fulltext="${bootInstance.recordCount?c}">${bootInstance.recordCount?c}</span></td>
                        <td><span class="truncate" data-fulltext="${bootInstance.executingCount?c}">${bootInstance.executingCount?c}</span></td>
                        <td>
                            <span class="truncate" data-fulltext="${(bootInstance.totalCount)?string(',###')}">
                                ${(bootInstance.totalCount)?string(',###')}
                            </span>
                        </td>
                        <td><span class="truncate" data-fulltext="${bootInstance.yesterdayAttemptCount?string(',###')}">${bootInstance.yesterdayAttemptCount?string(',###')}</span></td>
                        <td><span class="truncate" data-fulltext="${bootInstance.currentAttemptCount?string(',###')}">${bootInstance.currentAttemptCount?string(',###')}</span></td>
                        <td><span class="truncate" data-fulltext="${bootInstance.failCount?string(',###')}">${bootInstance.failCount?string(',###')}</span></td>
                        <td><span class="truncate" data-fulltext="${bootInstance.successCount?string(',###')}">${bootInstance.successCount?string(',###')}</span></td>
                        <#--<td><span class="truncate" data-fulltext="${bootInstance.addCount?string(',###')}">${bootInstance.addCount?string(',###')}</span></td>-->
                        <td>${bootInstance.architecture!''}</td>
                        <td><span class="truncate" data-fulltext="${bootInstance.createAtStr!''}">${bootInstance.createAtStr!''}</span></td>
                        <td>
                            <div class="dropdown">
                                <!-- 三点操作按钮 -->
                                <button class="dropdown-toggle btn">
                                    <i class="fas fa-ellipsis-h"></i>
                                </button>

                                <!-- 操作菜单 -->
                                <div class="dropdown-panel">
                                    <!-- 克隆开机 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.clone")}"
                                            onclick="handleCloneStart('${bootInstance.id?c}')">
                                        <i class="fas fa-clone"></i><span>${msg.get("openBoot.clone")}</span>
                                    </button>
                                    <!-- 启动 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.startOpen")}"
                                            onclick="handleStart('${bootInstance.id?c}')">
                                        <i class="fas fa-play"></i><span>${msg.get("openBoot.startOpen")}</span>
                                    </button>

                                    <!-- 停止 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.stopOpen")}"
                                            onclick="handleStop('${bootInstance.id?c}')">
                                        <i class="fas fa-stop"></i><span>${msg.get("openBoot.stopOpen")}</span>
                                    </button>

                                    <!-- 开机详情 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.detailOpen")}"
                                            onclick="openDetailModal('${bootInstance.id?c}')">
                                        <i class="fas fa-info-circle"></i><span>${msg.get("openBoot.detailOpen")}</span>
                                    </button>

                                    <!-- 添加抢机配置 -->
                                    <a href="/tenants/bootPage?tenantId=${bootInstance.tenantId?c}" class="dropdown-item" title="${msg.get("openBoot.configOpen")}">
                                        <i class="fas fa-plus-circle"></i><span>${msg.get("openBoot.configOpen")}</span>
                                    </a>

                                    <!-- 删除 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.deleteOpen")}"
                                            onclick="handleDelete('${bootInstance.id?c}')">
                                        <i class="fas fa-trash"></i><span>${msg.get("openBoot.deleteOpen")}</span>
                                    </button>

                                    <!-- 手动抢机 -->
                                    <button class="dropdown-item"
                                            title="${msg.get("openBoot.manualOpen")}"
                                            onclick="handleManualBoot('${bootInstance.id?c}')">
                                        <i class="fas fa-bolt"></i><span>${msg.get("openBoot.manualOpen")}</span>
                                    </button>

                                </div>
                            </div>
                        </td>

                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

        <!-- 移动端底部批量操作栏 -->
        <div class="mob-batch-bar">
            <button class="mob-batch-btn mob-btn-start" onclick="handleBatchStart()">
                <i class="fas fa-play-circle"></i>
                <span>${msg.get("openBoot.open")}</span>
            </button>
            <button class="mob-batch-btn mob-btn-stop" onclick="handleBatchStop()">
                <i class="fas fa-stop-circle"></i>
                <span>${msg.get("openBoot.stop")}</span>
            </button>
            <button class="mob-batch-btn mob-btn-reset" onclick="handleBatchFail()">
                <i class="fas fa-redo-alt"></i>
                <span>${msg.get("openBoot.reset")}</span>
            </button>
        </div>

        <@pagination
        url="/boot/fullBootList"
        page=currentPage!0
        size=size!20
        totalPages=totalPages!1
        totalElements=totalElements!0
        textShow=msg.get("page.show")
        textItem=msg.get("page.item")
        textPrev=msg.get("page.prev")
        textNext=msg.get("page.next")
        textJump=msg.get("page.jump")
        textPage=msg.get("page.page")
        textTotal=msg.get("page.total")
        />
        </div><!-- /.page-card -->
    </main>
</div>

<!-- 开机详情模态框 -->
<div id="detailModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h2 class="modal-title">${msg.get("openBoot.detailOpen")}</h2>
            <button class="close-btn" onclick="closeDetailModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-content">
            <div id="detailContent">
                <!-- 详情内容将通过JavaScript动态加载 -->
                <div style="text-align: center; padding: 20px;">
                    <i class="fas fa-spinner fa-spin" style="font-size: 24px; color: var(--accent-blue);"></i>
                    <p style="margin-top: 10px;">loading...</p>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- 修改详情模态框 -->
<div id="editDetailModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h2 class="modal-title">${msg.get("openBoot.editOpen")}</h2>
            <button class="close-btn" onclick="closeEditDetailModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-content">
            <form id="editDetailForm" onsubmit="handleEditDetail(event)">
                <input type="hidden" id="editDetailId" name="id">
                <div class="form-group">
                    <label for="editDetailOcpu">OCPU:</label>
                    <input type="number" id="editDetailOcpu" name="ocpu" class="form-input" required min="1" step="1">
                </div>
                <div class="form-group">
                    <label for="editDetailMemory">${msg.get("openBoot.mem")}(GB):</label>
                    <input type="number" id="editDetailMemory" name="memory" class="form-input" required min="1" step="1">
                </div>
                <div class="form-group">
                    <label for="editDetailDisk">${msg.get("openBoot.volume")}(GB):</label>
                    <input type="number" id="editDetailDisk" name="disk" class="form-input" required min="1" step="1">
                </div>
                <div class="form-group">
                    <label for="editDetailLoopTime">${msg.get("openBoot.time")}:</label>
                    <input type="number" id="editDetailLoopTime" name="loopTime" class="form-input" required min="1" step="1">
                </div>
                <div class="form-group">
                    <label for="editDetailDayGap">${msg.get("openBoot.range")}:</label>
                    <input type="text" id="editDetailDayGap" name="dayGap"
                           placeholder="${msg.get("openBoot.timeRangeExample")}"
                           class="form-input">
                </div>

                <div class="form-group">
                    <label for="editDetailPassword">${msg.get("openBoot.rootPass")}:</label>
                    <input type="text" id="editDetailPassword" name="rootPassword" class="form-input" required>
                </div>
                <div class="modal-actions">
                    <button type="submit" class="btn btn-primary">${msg.get("common.save")}</button>
                    <button type="button" class="btn btn-secondary" onclick="closeEditDetailModal()">${msg.get("common.cancel")}</button>
                </div>
            </form>
        </div>
    </div>
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
        openBoot_yesterday: "${msg.get('openBoot.yesterday')?js_string}",
        openBoot_today: "${msg.get('openBoot.today')?js_string}",
        openBoot_fail: "${msg.get('openBoot.fail')?js_string}",
        openBoot_os: "${msg.get('openBoot.os')?js_string}",
        openBoot_config: "${msg.get('openBoot.config')?js_string}",
        openBoot_range: "${msg.get('openBoot.range')?js_string}",
        openBoot_time: "${msg.get('openBoot.time')?js_string}",
        openBoot_rootPass: "${msg.get('openBoot.rootPass')?js_string}",
        openBoot_status: "${msg.get('openBoot.status')?js_string}",
        openBoot_startTime: "${msg.get('openBoot.startTime')?js_string}",
        openBoot_action: "${msg.get('openBoot.action')?js_string}",
        openBoot_stopOpen: "${msg.get('openBoot.stopOpen')?js_string}",
        openBoot_startOpen: "${msg.get('openBoot.startOpen')?js_string}",
        openBoot_updateConfig: "${msg.get('openBoot.updateConfig')?js_string}",
        openBoot_delete: "${msg.get('openBoot.delete')?js_string}",
        openBoot_log: "${msg.get('openBoot.log')?js_string}",
        openBoot_nDetailData: "${msg.get('openBoot.nDetailData')?js_string}",
        openBoot_loadingFail: "${msg.get('openBoot.loadingFail')?js_string}",
        openBoot_noDetail: "${msg.get('openBoot.noDetail')?js_string}",
        openBoot_timeForError: "${msg.get('openBoot.timeForError')?js_string}",
        openBoot_timeForExample: "${msg.get('openBoot.timeForExample')?js_string}",
        openBoot_timeRangeForExample: "${msg.get('openBoot.timeRangeForExample')?js_string}",
        openBoot_timeRangeNoSupport: "${msg.get('openBoot.timeRangeNoSupport')?js_string}",
        common_save: "${msg.get('common.save')?js_string}",
        openBoot_batchClearFailCount: "${msg.get('openBoot.batchClearFailCount')?js_string}",
        openBoot_manalConfirm: "${msg.get('openBoot.manalConfirm')?js_string}",
        common_loading: "${msg.get('common.loading')?js_string}",
        notification_plzSelectAiTenantName: "${msg.get('notification.plzSelectAiTenantName')?js_string}",
        openBoot_selectRegion: "${msg.get('openBoot.selectRegion')?js_string}",
        openBoot_noRegion: "${msg.get('openBoot.noRegion')?js_string}",
        openBoot_startOpen: "${msg.get('openBoot.startOpen')?js_string}",
        openBoot_stopOpen: "${msg.get('openBoot.stopOpen')?js_string}",
        openBoot_startBootTask: "${msg.get('openBoot.startBootTask')?js_string}",
        openBoot_stopBootTask: "${msg.get('openBoot.stopBootTask')?js_string}",
        openBoot_noOpen: "${msg.get('openBoot.noOpen')?js_string}",
        openBoot_alreadyOpen: "${msg.get('openBoot.alreadyOpen')?js_string}",
        openBoot_opening: "${msg.get('openBoot.opening')?js_string}",

    }
</script>
<!-- 开机日志抽屉 -->
<div id="bootLogDrawer" class="boot-log-drawer" aria-hidden="true">
    <div class="boot-log-drawer__mask" onclick="closeBootLogDrawer()"></div>
    <aside class="boot-log-drawer__panel" role="dialog" aria-labelledby="bootLogDrawerTitle">
        <header class="boot-log-drawer__header">
            <div class="boot-log-drawer__title">
                <i class="fas fa-rocket"></i>
                <span id="bootLogDrawerTitle">开机日志</span>
                <span class="boot-log-drawer__bootid" id="bootLogDrawerBootId"></span>
            </div>
            <div class="boot-log-drawer__actions">
                <span class="boot-log-drawer__status" id="bootLogDrawerStatus">
                    <span class="boot-log-drawer__status-dot"></span>
                    <span class="boot-log-drawer__status-text">未连接</span>
                </span>
                <label class="boot-log-drawer__autoscroll">
                    <input type="checkbox" id="bootLogAutoScroll" checked>
                    <span>自动滚动</span>
                </label>
                <button class="boot-log-drawer__close" onclick="closeBootLogDrawer()" title="关闭">
                    <i class="fas fa-times"></i>
                </button>
            </div>
        </header>
        <div class="boot-log-drawer__body" id="bootLogDrawerBody">
            <div class="boot-log-drawer__empty" id="bootLogDrawerEmpty">
                <i class="fas fa-hourglass-half"></i>
                <span>暂无日志,等待新日志推送...</span>
            </div>
        </div>
    </aside>
</div>

<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/full_machine_list.js"></script>

</body>
</html>