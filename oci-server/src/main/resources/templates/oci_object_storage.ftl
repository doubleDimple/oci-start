<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>${msg.get('storage.title')}</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <link rel="stylesheet" href="/css/app/oci_object_storage.css">
    <style>
        .load-more-btn {
            width: 100%; margin-top: 10px; border: 1px dashed var(--border);
            background: transparent; color: var(--text); padding: 8px;
            border-radius: 6px; cursor: pointer; transition: all 0.2s;
        }
        .load-more-btn:hover { background: var(--bg-hover); color: var(--accent); border-color: var(--accent); }
    </style>
</head>
<body>

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
        <div class="page-card">

            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-archive"></i>
                    <span>${msg.get('sidebar.oci.storage')}</span>
                </h1>
            </div>

            <div class="filter-bar">
                <span class="filter-label">${msg.get('storage.tenant.label')}</span>
                <div class="filter-select-wrap">
                    <select id="tenantSelect"
                            data-custom-select data-searchable data-page-size="5"
                            data-placeholder="${msg.get('storage.tenant.select')}"
                            onchange="onTenantChange()">
                        <option value="">${msg.get('storage.tenant.select')}</option>
                    </select>
                </div>
                <button class="btn btn-secondary btn-sm" onclick="refreshBuckets()">
                    <i class="fas fa-sync-alt"></i> ${msg.get('storage.btn.refresh')}
                </button>
            </div>

            <div class="storage-grid">

                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title"><i class="fas fa-database"></i> ${msg.get('storage.bucket.title')}</h3>
                        <button class="btn btn-primary btn-sm" onclick="showCreateBucketModal()">
                            <i class="fas fa-plus"></i> ${msg.get('storage.bucket.create')}
                        </button>
                    </div>
                    <div class="panel-body" style="display:flex; flex-direction:column; max-height:100%; overflow:hidden;">
                        <div class="bucket-search">
                            <input type="text" id="bucketSearchInput" placeholder="${msg.get('storage.bucket.search.placeholder')}"
                                   oninput="filterBuckets(this.value)" />
                        </div>
                        <div class="bucket-list" id="bucketList" style="flex:1; overflow-y:auto; padding-bottom:10px;">
                            <div class="empty-state">
                                <i class="fas fa-cloud"></i>
                                <p>${msg.get('storage.bucket.empty.select')}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title">
                            <i class="fas fa-folder-open"></i> ${msg.get('storage.object.title')}
                            <div class="breadcrumb" id="objectBreadcrumb" style="display:none; margin-left:8px;">
                                <span class="bc-sep">/</span>
                                <span class="bc-active" id="breadcrumbBucketName"></span>
                            </div>
                        </h3>
                        <div id="objectHeaderActions" style="display:none; gap:6px;">
                            <button class="btn btn-primary btn-sm" onclick="triggerUpload()">
                                <i class="fas fa-upload"></i> ${msg.get('storage.object.btn.upload')}
                            </button>
                            <button class="btn btn-secondary btn-sm" onclick="refreshObjects()">
                                <i class="fas fa-sync-alt"></i> ${msg.get('storage.object.btn.refresh')}
                            </button>
                            <input type="file" id="uploadFileInput" multiple style="display:none" onchange="handleFileSelect(this.files)">
                        </div>
                    </div>
                    <div class="panel-body">
                        <div class="empty-state" id="objectEmptyState">
                            <i class="fas fa-hand-point-left"></i>
                            <p>${msg.get('storage.object.empty.select')}</p>
                        </div>

                        <div id="objectTableContainer" style="display:none; flex:1; min-height:0; flex-direction:column;">
                            <div class="object-table-wrap" id="objectTableWrap">
                                <table class="object-table">
                                    <thead>
                                    <tr>
                                        <th style="width:38%">${msg.get('storage.object.col.name')}</th>
                                        <th style="width:13%">${msg.get('storage.object.col.size')}</th>
                                        <th style="width:20%">${msg.get('storage.object.col.modified')}</th>
                                        <th style="width:29%">${msg.get('storage.object.col.actions')}</th>
                                    </tr>
                                    </thead>
                                    <tbody id="objectTableBody">
                                    </tbody>
                                </table>
                            </div>
                            <div class="pagination-row" id="objectPaginationRow">
                                <span class="pagination-info" id="objectPaginationInfo"></span>
                                <div class="pagination-nav" id="objectPaginationNav" style="gap:8px; display:flex;">
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div></div></main>
</div><div class="modal-overlay" id="uploadProgressModal">
    <div class="modal-box" style="width:480px;">
        <div class="modal-header">
            <h4 class="modal-title"><i class="fas fa-upload"></i> ${msg.get('storage.upload.title')}</h4>
            <button class="modal-close" id="uploadCancelBtn" onclick="cancelUpload()"><i class="fas fa-times"></i></button>
        </div>
        <div id="uploadFileList" style="max-height:280px;overflow-y:auto;margin-bottom:12px;"></div>
        <div id="uploadOverallWrap" style="display:none;">
            <div style="display:flex;justify-content:space-between;font-size:12px;color:var(--muted);margin-bottom:4px;">
                <span id="uploadOverallLabel">${msg.get('storage.upload.overall')}</span>
                <span id="uploadOverallPct">0%</span>
            </div>
            <div style="height:6px;background:var(--border);border-radius:3px;overflow:hidden;">
                <div id="uploadOverallBar" style="height:100%;background:var(--accent);border-radius:3px;width:0;transition:width .2s;"></div>
            </div>
        </div>
        <div class="modal-footer" style="margin-top:14px;">
            <button class="btn btn-secondary btn-sm" onclick="cancelUpload()">${msg.get('storage.upload.cancel')}</button>
            <button class="btn btn-primary btn-sm" id="uploadDoneBtn" style="display:none;" onclick="closeUploadModal()">${msg.get('storage.upload.complete')}</button>
        </div>
    </div>
</div>

<div class="modal-overlay" id="createBucketModal">
    <div class="modal-box">
        <div class="modal-header">
            <h4 class="modal-title"><i class="fas fa-plus-circle"></i> ${msg.get('storage.bucket.modal.title')}</h4>
            <button class="modal-close" onclick="closeCreateBucketModal()"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div class="form-group">
                <label class="form-label">${msg.get('storage.bucket.modal.name')} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="newBucketName" class="form-control" placeholder="${msg.get('storage.bucket.modal.name.placeholder')}" />
            </div>
            <div class="form-group">
                <label class="form-label">${msg.get('storage.bucket.modal.access')}</label>
                <select id="newBucketAccessType" class="form-control">
                    <option value="NoPublicAccess">${msg.get('storage.bucket.modal.access.private')}</option>
                    <option value="ObjectRead">${msg.get('storage.bucket.modal.access.read')}</option>
                    <option value="ObjectReadWithoutList">${msg.get('storage.bucket.modal.access.readNoList')}</option>
                </select>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary btn-sm" onclick="closeCreateBucketModal()">${msg.get('storage.bucket.modal.btn.cancel')}</button>
            <button class="btn btn-primary btn-sm" onclick="submitCreateBucket()">
                <i class="fas fa-check"></i> ${msg.get('storage.bucket.modal.btn.create')}
            </button>
        </div>
    </div>
</div>

<script src="/js/sweetalert2.min.js"></script>
<script src="/js/common/jquery.min.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>

<script>
    /* ============================================================
       i18n strings (injected from server)
    ============================================================ */
    const I18N = {
        tenantSelect:        '${msg.get("storage.tenant.select")}',
        tenantLoading:       '${msg.get("storage.tenant.loading")}',
        tenantLoadFail:      '${msg.get("storage.tenant.loadFail")}',
        bucketEmptySelect:   '${msg.get("storage.bucket.empty.select")}',
        bucketEmptyNone:     '${msg.get("storage.bucket.empty.none")}',
        bucketLoadMore:      '${msg.get("storage.bucket.loadMore")}',
        bucketLoading:       '${msg.get("storage.bucket.loading")}',
        bucketNoTenant:      '${msg.get("storage.bucket.noTenant")}',
        bucketAccessPrivate: '${msg.get("storage.bucket.access.private")}',
        bucketAccessPublic:  '${msg.get("storage.bucket.access.publicRead")}',
        bucketAccessPublicR: '${msg.get("storage.bucket.access.publicReadNoList")}',
        bucketDeleteTitle:   '${msg.get("storage.bucket.delete.title")}',
        bucketDeleteConfirm: '${msg.get("storage.bucket.delete.confirm")}',
        bucketDeleteSuccess: '${msg.get("storage.bucket.delete.success")}',
        bucketDeleteFail:    '${msg.get("storage.bucket.delete.fail")}',
        objectEmptyNone:     '${msg.get("storage.object.empty.none")}',
        objectLoading:       '${msg.get("storage.object.loading")}',
        objectNetworkError:  '${msg.get("storage.object.error.network")}',
        objectPageInfo:      '${msg.get("storage.object.page.info")}',
        objectPagePrev:      '${msg.get("storage.object.page.prev")}',
        objectPageNext:      '${msg.get("storage.object.page.next")}',
        objectDeleteTitle:   '${msg.get("storage.object.delete.title")}',
        objectDeleteSuccess: '${msg.get("storage.object.delete.success")}',
        objectDeleteFail:    '${msg.get("storage.object.delete.fail")}',
        presignTitle:        '${msg.get("storage.object.presign.title")}',
        presignCopied:       '${msg.get("storage.object.presign.copied")}',
        presignFail:         '${msg.get("storage.object.presign.fail")}',
        previewFail:         '${msg.get("storage.object.preview.fail")}',
        previewLoadFail:     '${msg.get("storage.object.preview.loadFail")}',
        btnClose:            '${msg.get("storage.object.btn.close")}',
        btnDownload:         '${msg.get("storage.object.btn.download")}',
        uploadWaiting:       '${msg.get("storage.upload.waiting")}',
        uploadDone:          '${msg.get("storage.upload.done")}',
        uploadFail:          '${msg.get("storage.upload.fail")}',
        uploadResuming:      '${msg.get("storage.upload.resuming")}',
        resumeTitle:         '${msg.get("storage.upload.resume.title")}',
        resumeConfirm:       '${msg.get("storage.upload.resume.confirm")}',
        resumeBtn:           '${msg.get("storage.upload.resume.btn")}',
        resumeIgnore:        '${msg.get("storage.upload.resume.ignore")}',
        reselectTitle:       '${msg.get("storage.upload.resume.reselect.title")}',
        reselectDesc:        '${msg.get("storage.upload.resume.reselect.desc")}',
        reselectBtn:         '${msg.get("storage.upload.resume.reselect.btn")}',
        bucketCreateLoading: '${msg.get("storage.bucket.create.loading")}',
        bucketCreateSuccess: '${msg.get("storage.bucket.create.success")}',
        bucketCreateFail:    '${msg.get("storage.bucket.create.fail")}',
        bucketCreateNameReq: '${msg.get("storage.bucket.create.nameRequired")}',
        loadingBuckets:      '${msg.get("storage.loading.buckets")}',
        loadingObjects:      '${msg.get("storage.loading.objects")}',
        cancel:              '${msg.get("common.cancel")}',
        confirm:             '${msg.get("common.confirm")}',
        delete_:             '${msg.get("common.delete")}',
        networkError:        '${msg.get("common.network.error")}',
    };

    /* ============================================================
       State
    ============================================================ */
    let currentTenantId = null;
    let currentNamespace = null;
    let currentBucketName = null;

    // Bucket Pagination State
    let allBuckets = [];
    let bucketNextPageToken = null;
    let hasMoreBuckets = false;

    // Object Pagination State
    let allObjects = [];
    let objTokens = [null];
    let objCurrentPageIdx = 0;
    let objHasNext = false;
    const OBJ_LIMIT = 5;

    /* ============================================================
       CSRF helper
    ============================================================ */
    function getCsrf() {
        return document.querySelector('meta[name="_csrf"]').getAttribute('content');
    }

    function postJson(url, data) {
        return fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrf()
            },
            body: JSON.stringify(data)
        }).then(r => r.json());
    }

    function getJson(url) {
        return fetch(url, {
            headers: { 'X-CSRF-TOKEN': getCsrf() }
        }).then(r => r.json());
    }

    /* ============================================================
       Init
    ============================================================ */
    document.addEventListener('DOMContentLoaded', function () {
        loadTenants();
    });

    /* ============================================================
       Tenant
    ============================================================ */
    function loadTenants() {
        const sel = document.getElementById('tenantSelect');
        sel.innerHTML = '<option value="">' + I18N.tenantLoading + '</option>';
        sel.disabled = true;

        getJson('/tenants/listParentTenants')
            .then(data => {
                sel.innerHTML = '<option value="">' + I18N.tenantSelect + '</option>';
                sel.disabled = false;
                if (Array.isArray(data)) {
                    data.sort((a, b) => (a.userName && b.userName) ? a.userName.localeCompare(b.userName) : 0);
                    data.forEach(t => {
                        const opt = document.createElement('option');
                        opt.value = t.id;
                        opt.textContent = t.userName || t.tenancyName || ('租户 ' + t.id);
                        sel.appendChild(opt);
                    });
                }
                if (window.CustomSelect) CustomSelect.init(sel);
            })
            .catch(err => {
                console.error('加载租户失败', err);
                sel.innerHTML = '<option value="">' + I18N.tenantLoadFail + '</option>';
                sel.disabled = false;
            });
    }

    function onTenantChange() {
        const sel = document.getElementById('tenantSelect');
        currentTenantId = sel.value || null;
        currentNamespace = null;
        currentBucketName = null;
        allBuckets = [];
        bucketNextPageToken = null;

        clearObjectPanel();

        if (!currentTenantId) {
            renderBuckets();
            return;
        }
        loadBuckets(false);
    }

    /* ============================================================
       Namespace
    ============================================================ */
    async function ensureNamespace() {
        if (currentNamespace) return currentNamespace;
        const res = await getJson('/oci/storage/namespace?tenantId=' + currentTenantId);
        if (res.success && res.data) {
            currentNamespace = res.data.namespace;
        }
        return currentNamespace;
    }

    /* ============================================================
       Buckets
    ============================================================ */
    function loadBuckets(isLoadMore = false) {
        if (!currentTenantId) return;
        const list = document.getElementById('bucketList');

        if (!isLoadMore) {
            list.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>' + I18N.bucketLoading + '</p></div>';
            bucketNextPageToken = null;
            allBuckets = [];
        } else {
            const btn = document.getElementById('btnLoadMoreBuckets');
            if(btn) btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + I18N.bucketLoading;
        }

        let url = '/oci/storage/buckets?tenantId=' + currentTenantId + '&limit=5';
        if (isLoadMore && bucketNextPageToken) {
            url += '&pageToken=' + encodeURIComponent(bucketNextPageToken);
        }

        getJson(url)
            .then(res => {
                if (res.success) {
                    const newItems = res.data.items || [];
                    if (isLoadMore) {
                        allBuckets = allBuckets.concat(newItems);
                    } else {
                        allBuckets = newItems;
                    }
                    bucketNextPageToken = res.data.nextPage;
                    hasMoreBuckets = !!bucketNextPageToken;
                    filterBuckets(document.getElementById('bucketSearchInput').value);
                } else {
                    if (!isLoadMore) list.innerHTML = '<div class="empty-state"><i class="fas fa-exclamation-circle"></i><p>' + (res.message || I18N.networkError) + '</p></div>';
                }
            })
            .catch(err => {
                console.error('加载存储桶失败', err);
                if (!isLoadMore) list.innerHTML = '<div class="empty-state"><i class="fas fa-exclamation-circle"></i><p>' + I18N.networkError + '</p></div>';
            });
    }

    function refreshBuckets() {
        if (!currentTenantId) {
            Swal.fire({ icon: 'warning', title: I18N.bucketNoTenant, timer: 1500, showConfirmButton: false });
            return;
        }
        loadBuckets(false);
    }

    function filterBuckets(keyword) {
        const kw = keyword.trim().toLowerCase();
        const filtered = kw ? allBuckets.filter(b => b.name.toLowerCase().includes(kw)) : allBuckets;
        renderBuckets(filtered);
    }

    function renderBuckets(bucketsToRender = allBuckets) {
        const list = document.getElementById('bucketList');
        if (!bucketsToRender || bucketsToRender.length === 0) {
            list.innerHTML = '<div class="empty-state"><i class="fas fa-database"></i><p>' +
                (currentTenantId ? I18N.bucketEmptyNone : I18N.bucketEmptySelect) + '</p></div>';
            return;
        }

        list.innerHTML = '';
        bucketsToRender.forEach(b => {
            const div = document.createElement('div');
            div.className = 'bucket-item' + (b.name === currentBucketName ? ' active' : '');
            div.dataset.name = b.name;
            div.dataset.namespace = b.namespace;
            div.onclick = () => selectBucket(b.name, b.namespace);

            const accessLabel = getAccessLabel(b.publicAccess);
            const created = b.timeCreated ? formatDate(b.timeCreated) : '';

            div.innerHTML =
                '<div class="bucket-item-info">' +
                '  <div class="bucket-name" title="' + escHtml(b.name) + '">' + escHtml(b.name) + '</div>' +
                '  <div class="bucket-meta">' + created + '</div>' +
                '</div>' +
                '<div class="bucket-item-actions">' +
                '  <span class="access-badge ' + accessLabel.cls + '">' + accessLabel.label + '</span>' +
                '  <button class="btn btn-danger btn-xs" onclick="confirmDeleteBucket(event, \'' + escAttr(b.name) + '\',\'' + escAttr(b.namespace) + '\')" title="${msg.get("common.delete")}" style="margin-left:4px;"><i class="fas fa-trash"></i></button>' +
                '</div>';
            list.appendChild(div);
        });

        if (hasMoreBuckets && !document.getElementById('bucketSearchInput').value.trim()) {
            const moreBtn = document.createElement('button');
            moreBtn.id = 'btnLoadMoreBuckets';
            moreBtn.className = 'load-more-btn';
            moreBtn.innerHTML = I18N.bucketLoadMore;
            moreBtn.onclick = () => loadBuckets(true);
            list.appendChild(moreBtn);
        }
    }

    function getAccessLabel(type) {
        if (!type || type === 'NoPublicAccess') return { cls: 'private', label: '<i class="fas fa-lock"></i>' + I18N.bucketAccessPrivate };
        if (type === 'ObjectRead') return { cls: 'public', label: '<i class="fas fa-eye"></i>' + I18N.bucketAccessPublic };
        if (type === 'ObjectReadWithoutList') return { cls: 'public-r', label: '<i class="fas fa-eye-slash"></i>' + I18N.bucketAccessPublicR };
        return { cls: 'private', label: '<i class="fas fa-lock"></i>' + type };
    }

    function confirmDeleteBucket(event, bucketName, namespace) {
        event.stopPropagation();
        Swal.fire({
            title: I18N.bucketDeleteTitle,
            html: I18N.bucketDeleteConfirm,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: I18N.delete_,
            cancelButtonText: I18N.cancel,
            confirmButtonColor: '#d33'
        }).then((result) => {
            if (result.isConfirmed) {
                postJson('/oci/storage/bucket/delete', {
                    tenantId: currentTenantId,
                    namespace: namespace,
                    bucketName: bucketName
                }).then(res => {
                    if (res.success) {
                        Swal.fire({ icon: 'success', title: I18N.bucketDeleteSuccess, timer: 1500, showConfirmButton: false });
                        if (currentBucketName === bucketName) {
                            currentBucketName = null;
                            clearObjectPanel();
                        }
                        loadBuckets(false);
                    } else {
                        Swal.fire({ icon: 'error', title: I18N.bucketDeleteFail, text: res.message || I18N.networkError });
                    }
                }).catch(err => {
                    Swal.fire({ icon: 'error', title: I18N.bucketDeleteFail, text: I18N.networkError });
                });
            }
        });
    }

    /* ============================================================
       Objects
    ============================================================ */
    function selectBucket(bucketName, namespace) {
        currentBucketName = bucketName;
        currentNamespace = namespace;

        document.querySelectorAll('.bucket-item').forEach(el => {
            el.classList.toggle('active', el.dataset.name === bucketName);
        });

        document.getElementById('breadcrumbBucketName').textContent = bucketName;
        document.getElementById('objectBreadcrumb').style.display = 'flex';
        document.getElementById('objectHeaderActions').style.display = 'flex';

        loadObjects(true); // true 表示从第一页开始加载
        checkResumeableUploads(bucketName);
    }

    function loadObjects(isNewSearch = false) {
        if (!currentTenantId || !currentBucketName || !currentNamespace) return;

        if (isNewSearch) {
            objTokens = [null];
            objCurrentPageIdx = 0;
        }

        const currentToken = objTokens[objCurrentPageIdx];
        let url = '/oci/storage/objects?tenantId=' + currentTenantId +
            '&namespace=' + encodeURIComponent(currentNamespace) +
            '&bucketName=' + encodeURIComponent(currentBucketName) +
            '&limit=' + OBJ_LIMIT;

        if (currentToken) {
            url += '&startToken=' + encodeURIComponent(currentToken);
        }

        showObjectLoading();

        getJson(url)
            .then(res => {
                if (res.success) {
                    allObjects = res.data.items || [];
                    const nextStartWith = res.data.nextStartWith;

                    if (nextStartWith) {
                        objTokens[objCurrentPageIdx + 1] = nextStartWith;
                        objHasNext = true;
                    } else {
                        objHasNext = false;
                    }

                    renderObjects();
                } else {
                    showObjectError(res.message || I18N.networkError);
                }
            })
            .catch(err => {
                console.error('加载对象失败', err);
                showObjectError(I18N.networkError);
            });
    }

    function refreshObjects() {
        if (currentBucketName) loadObjects(false); // 刷新当前页
    }

    function showObjectLoading() {
        document.getElementById('objectEmptyState').style.display = 'none';
        const container = document.getElementById('objectTableContainer');
        container.style.display = 'flex';
        const body = document.getElementById('objectTableBody');
        body.innerHTML = '<tr class="loading-row"><td colspan="4"><i class="fas fa-spinner fa-spin"></i> ' + I18N.objectLoading + '</td></tr>';
        document.getElementById('objectPaginationNav').innerHTML = '';
        document.getElementById('objectPaginationInfo').textContent = '';
    }

    function showObjectError(errMsg) {
        document.getElementById('objectEmptyState').style.display = 'none';
        const container = document.getElementById('objectTableContainer');
        container.style.display = 'flex';
        const body = document.getElementById('objectTableBody');
        body.innerHTML = '<tr class="loading-row"><td colspan="4"><i class="fas fa-exclamation-circle"></i> ' + escHtml(errMsg) + '</td></tr>';
    }

    function clearObjectPanel() {
        document.getElementById('objectEmptyState').style.display = 'flex';
        document.getElementById('objectTableContainer').style.display = 'none';
        document.getElementById('objectBreadcrumb').style.display = 'none';
        document.getElementById('objectHeaderActions').style.display = 'none';
        document.getElementById('objectTableBody').innerHTML = '';
        document.getElementById('objectPaginationNav').innerHTML = '';
        document.getElementById('objectPaginationInfo').textContent = '';
    }

    function renderObjects() {
        document.getElementById('objectEmptyState').style.display = 'none';
        const container = document.getElementById('objectTableContainer');
        container.style.display = 'flex';

        const body = document.getElementById('objectTableBody');

        if (allObjects.length === 0) {
            body.innerHTML = '<tr class="loading-row"><td colspan="4">' + I18N.objectEmptyNone + '</td></tr>';
        } else {
            body.innerHTML = '';
            allObjects.forEach(obj => {
                const tr = document.createElement('tr');
                tr.innerHTML =
                    '<td class="object-name-cell" title="' + escHtml(obj.name) + '">' + escHtml(obj.name) + '</td>' +
                    '<td>' + formatSize(obj.size) + '</td>' +
                    '<td>' + (obj.timeModified ? formatDate(obj.timeModified) : '-') + '</td>' +
                    '<td><div class="object-actions">' +
                    (isPreviewable(obj.name) ? '  <button class="btn btn-ghost btn-xs" onclick="previewObject(\'' + escAttr(obj.name) + '\')" title="预览"><i class="fas fa-eye"></i></button>' : '') +
                    '  <button class="btn btn-ghost btn-xs" onclick="downloadObject(\'' + escAttr(obj.name) + '\')" title="下载"><i class="fas fa-download"></i></button>' +
                    '  <button class="btn btn-ghost btn-xs" onclick="getPresignedUrl(\'' + escAttr(obj.name) + '\')" title="获取预签名链接"><i class="fas fa-link"></i></button>' +
                    '  <button class="btn btn-danger btn-xs" onclick="confirmDeleteObject(\'' + escAttr(obj.name) + '\')" title="删除"><i class="fas fa-trash"></i></button>' +
                    '</div></td>';
                body.appendChild(tr);
            });
        }

        const paginationRow = document.getElementById('objectPaginationRow');
        paginationRow.style.display = (objCurrentPageIdx === 0 && !objHasNext) ? 'none' : 'flex';

        const info = document.getElementById('objectPaginationInfo');
        info.textContent = I18N.objectPageInfo.replace('{0}', objCurrentPageIdx + 1);

        const nav = document.getElementById('objectPaginationNav');
        nav.innerHTML = '';

        const prevBtn = document.createElement('button');
        prevBtn.className = 'btn btn-secondary btn-sm';
        prevBtn.innerHTML = '<i class="fas fa-chevron-left"></i> ' + I18N.objectPagePrev;
        prevBtn.disabled = objCurrentPageIdx === 0;
        prevBtn.onclick = () => { objCurrentPageIdx--; loadObjects(false); };
        nav.appendChild(prevBtn);

        const nextBtn = document.createElement('button');
        nextBtn.className = 'btn btn-secondary btn-sm';
        nextBtn.innerHTML = I18N.objectPageNext + ' <i class="fas fa-chevron-right"></i>';
        nextBtn.disabled = !objHasNext;
        nextBtn.onclick = () => { objCurrentPageIdx++; loadObjects(false); };
        nav.appendChild(nextBtn);
    }

    /* ── Resume check ── */
    function checkResumeableUploads(bucketName) {
        if (!currentTenantId) return;
        getJson('/oci/storage/object/multipart/resumeable?tenantId=' + currentTenantId + '&bucketName=' + encodeURIComponent(bucketName))
            .then(function(res) {
                if (res.success && res.data && res.data.length > 0) {
                    showResumePrompt(res.data);
                }
            }).catch(function() {});
    }

    function showResumePrompt(records) {
        var listHtml = records.map(function(r) {
            var pct = r.totalParts > 0 ? Math.round(r.completedPartCount / r.totalParts * 100) : 0;
            var size = formatSize(r.totalSize);
            return '<div style="padding:6px 0;border-bottom:1px solid var(--border);font-size:12px;">' +
                '<div style="font-weight:500;color:var(--text);margin-bottom:3px;">' + escHtml(r.objectName) + '</div>' +
                '<div style="color:var(--muted);">' + size + ' · ' + r.completedPartCount + '/' + r.totalParts + ' (' + pct + '%) · ' + (r.createTime || '') + '</div>' +
                '</div>';
        }).join('');

        Swal.fire({
            title: I18N.resumeTitle,
            html: '<div style="text-align:left;max-height:200px;overflow-y:auto;">' + listHtml + '</div>' +
                '<p style="margin-top:12px;font-size:13px;color:var(--muted);">' + I18N.resumeConfirm + '</p>',
            icon: 'info',
            showCancelButton: true,
            confirmButtonText: I18N.resumeBtn,
            cancelButtonText: I18N.resumeIgnore,
            width: 500
        }).then(function(result) {
            if (result.isConfirmed) {
                resumeUploads(records);
            }
        });
    }

    function resumeUploads(records) {
        Swal.fire({
            icon: 'info',
            title: I18N.reselectTitle,
            html: I18N.reselectDesc + '<br>' +
                records.map(function(r) { return '<b>' + escHtml(r.objectName) + '</b>'; }).join('<br>'),
            confirmButtonText: I18N.reselectBtn
        }).then(function(result) {
            if (result.isConfirmed) {
                window._resumeContext = records;
                document.getElementById('uploadFileInput').value = '';
                document.getElementById('uploadFileInput').click();
            }
        });
    }

    /* ============================================================
       Delete Object
    ============================================================ */
    function confirmDeleteObject(objectName) {
        Swal.fire({
            title: I18N.objectDeleteTitle,
            html: '<strong>' + escHtml(objectName) + '</strong><br>' + I18N.objectDeleteTitle,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: I18N.delete_,
            cancelButtonText: I18N.cancel,
            confirmButtonColor: '#ff6b6b'
        }).then(result => {
            if (result.isConfirmed) {
                deleteObject(objectName);
            }
        });
    }

    function deleteObject(objectName) {
        postJson('/oci/storage/object/delete', {
            tenantId: currentTenantId,
            namespace: currentNamespace,
            bucketName: currentBucketName,
            objectName: objectName
        }).then(res => {
            if (res.success) {
                Swal.fire({ icon: 'success', title: I18N.objectDeleteSuccess, timer: 1500, showConfirmButton: false });
                loadObjects(false);
            } else {
                Swal.fire({ icon: 'error', title: I18N.objectDeleteFail, text: res.message || I18N.networkError });
            }
        }).catch(err => {
            console.error('删除对象失败', err);
            Swal.fire({ icon: 'error', title: I18N.objectDeleteFail, text: I18N.networkError });
        });
    }

    /* ============================================================
       Presigned URL
    ============================================================ */
    function getPresignedUrl(objectName) {
        postJson('/oci/storage/object/presigned', {
            tenantId: currentTenantId,
            namespace: currentNamespace,
            bucketName: currentBucketName,
            objectName: objectName,
            validitySeconds: 3600
        }).then(res => {
            if (res.success && res.data && res.data.url) {
                const url = res.data.url;
                if (navigator.clipboard && window.isSecureContext) {
                    navigator.clipboard.writeText(url).then(() => {
                        Swal.fire({
                            icon: 'success',
                            title: I18N.presignCopied,
                            html: '<div style="word-break:break-all;font-size:12px;color:var(--muted);">' + escHtml(url) + '</div>',
                            confirmButtonText: I18N.confirm
                        });
                    });
                } else {
                    Swal.fire({
                        icon: 'info',
                        title: I18N.presignTitle,
                        html: '<div style="word-break:break-all;font-size:12px;">' + escHtml(url) + '</div>',
                        confirmButtonText: I18N.btnClose
                    });
                }
            } else {
                Swal.fire({ icon: 'error', title: I18N.presignFail, text: res.message || I18N.networkError });
            }
        }).catch(err => {
            console.error('获取预签名URL失败', err);
            Swal.fire({ icon: 'error', title: I18N.presignFail, text: I18N.networkError });
        });
    }

    /* ============================================================
       Create Bucket Modal
    ============================================================ */
    function showCreateBucketModal() {
        if (!currentTenantId) {
            Swal.fire({ icon: 'warning', title: I18N.bucketNoTenant, timer: 1500, showConfirmButton: false });
            return;
        }
        document.getElementById('newBucketName').value = '';
        document.getElementById('newBucketAccessType').value = 'NoPublicAccess';
        document.getElementById('createBucketModal').classList.add('active');
    }

    function closeCreateBucketModal() {
        document.getElementById('createBucketModal').classList.remove('active');
    }

    function submitCreateBucket() {
        const bucketName = document.getElementById('newBucketName').value.trim();
        const accessType = document.getElementById('newBucketAccessType').value;

        if (!bucketName) {
            Swal.fire({ icon: 'warning', title: I18N.bucketCreateNameReq, timer: 1500, showConfirmButton: false });
            return;
        }

        const btn = document.querySelector('#createBucketModal .btn-primary');
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + I18N.bucketCreateLoading;

        postJson('/oci/storage/bucket/create', {
            tenantId: currentTenantId,
            bucketName: bucketName,
            publicAccessType: accessType
        }).then(res => {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-check"></i> ' + '${msg.get("storage.bucket.modal.btn.create")}';
            if (res.success) {
                closeCreateBucketModal();
                Swal.fire({ icon: 'success', title: I18N.bucketCreateSuccess, timer: 1500, showConfirmButton: false });
                loadBuckets(false);
            } else {
                Swal.fire({ icon: 'error', title: I18N.bucketCreateFail, text: res.message || I18N.networkError });
            }
        }).catch(err => {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-check"></i> ' + '${msg.get("storage.bucket.modal.btn.create")}';
            console.error('创建存储桶失败', err);
            Swal.fire({ icon: 'error', title: I18N.bucketCreateFail, text: I18N.networkError });
        });
    }

    document.getElementById('createBucketModal').addEventListener('click', function(e) {
        if (e.target === this) closeCreateBucketModal();
    });

    /* ============================================================
       Utilities
    ============================================================ */
    function formatSize(bytes) {
        if (bytes == null) return '-';
        if (bytes === 0) return '0 B';
        const units = ['B','KB','MB','GB','TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        return (bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1) + ' ' + units[Math.min(i, units.length - 1)];
    }

    function formatDate(str) {
        if (!str) return '';
        try {
            const d = new Date(str);
            if (isNaN(d.getTime())) return str;
            const pad = n => String(n).padStart(2, '0');
            return d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate()) +
                ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
        } catch(e) { return str; }
    }

    function escHtml(s) {
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    function escAttr(s) {
        return String(s).replace(/\\/g,'\\\\').replace(/'/g,"\\'");
    }

    /* ============================================================
       Upload
    ============================================================ */
    var MULTIPART_THRESHOLD = 50 * 1024 * 1024;   // 50 MB
    var CHUNK_SIZE           = 10 * 1024 * 1024;   // 10 MB per part

    var _uploadTasks    = [];
    var _uploadAborted  = false;
    var _activeXhr      = null;
    var _activeUploadId = null;
    var _activeTask     = null;

    function triggerUpload() {
        document.getElementById('uploadFileInput').value = '';
        document.getElementById('uploadFileInput').click();
    }

    function handleFileSelect(files) {
        if (!files || files.length === 0) return;
        _uploadTasks   = Array.from(files);
        _uploadAborted = false;
        var ctx = window._resumeContext || [];
        window._resumeContext = null;
        _uploadTasks.forEach(function(f) {
            var rec = ctx.find(function(r) { return r.objectName === f.name || r.objectName.endsWith('/' + f.name); });
            if (rec) f._resumeRecord = rec;
        });
        _activeXhr     = null;
        _activeUploadId = null;

        var list = document.getElementById('uploadFileList');
        list.innerHTML = '';
        _uploadTasks.forEach(function(f, i) {
            var row = document.createElement('div');
            row.id  = 'upload-row-' + i;
            row.style.cssText = 'margin-bottom:10px;';
            row.innerHTML =
                '<div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:3px;">' +
                '  <span style="color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:300px;" title="' + escHtml(f.name) + '">' + escHtml(f.name) + '</span>' +
                '  <span id="upload-pct-' + i + '" style="color:var(--muted);flex-shrink:0;margin-left:8px;">' + I18N.uploadWaiting + '</span>' +
                '</div>' +
                '<div style="height:4px;background:var(--border);border-radius:2px;overflow:hidden;">' +
                '  <div id="upload-bar-' + i + '" style="height:100%;background:var(--accent);border-radius:2px;width:0;transition:width .15s;"></div>' +
                '</div>';
            list.appendChild(row);
        });

        document.getElementById('uploadOverallWrap').style.display = 'block';
        document.getElementById('uploadDoneBtn').style.display = 'none';
        document.getElementById('uploadCancelBtn').style.display = '';
        document.getElementById('uploadProgressModal').classList.add('active');

        uploadSequential(0, 0);
    }

    function uploadSequential(idx, doneCount) {
        if (_uploadAborted) return;
        if (idx >= _uploadTasks.length) {
            setOverallProgress(100);
            document.getElementById('uploadCancelBtn').style.display = 'none';
            document.getElementById('uploadDoneBtn').style.display = '';
            loadObjects(true); // 上传完后回到第一页
            setTimeout(function() { closeUploadModal(); }, 1500); // 1.5秒后自动关闭
            return;
        }

        var file = _uploadTasks[idx];
        _activeTask = { idx: idx, file: file };

        if (file.size >= MULTIPART_THRESHOLD) {
            uploadMultipart(idx, file, function(ok) {
                if (!ok) setFilePct(idx, I18N.uploadFail, '#dc2626');
                uploadSequential(idx + 1, doneCount + (ok ? 1 : 0));
            });
        } else {
            uploadSmall(idx, file, function(ok) {
                if (!ok) setFilePct(idx, I18N.uploadFail, '#dc2626');
                uploadSequential(idx + 1, doneCount + (ok ? 1 : 0));
            });
        }
    }

    function uploadSmall(idx, file, cb) {
        var formData = new FormData();
        formData.append('tenantId', currentTenantId);
        formData.append('namespace', currentNamespace);
        formData.append('bucketName', currentBucketName);
        formData.append('file', file);

        var xhr = new XMLHttpRequest();
        _activeXhr = xhr;
        xhr.open('POST', '/oci/storage/object/upload');
        xhr.setRequestHeader('X-CSRF-TOKEN', getCsrf());

        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                var pct = Math.round(e.loaded / e.total * 100);
                setFileBar(idx, pct);
                setFilePct(idx, pct + '%');
                updateOverallProgress();
            }
        };
        xhr.onload = function() {
            try {
                var res = JSON.parse(xhr.responseText);
                if (res.success) {
                    setFileBar(idx, 100);
                    setFilePct(idx, I18N.uploadDone, 'var(--accent-g)');
                    cb(true);
                } else {
                    cb(false);
                }
            } catch(e) { cb(false); }
        };
        xhr.onerror = function() { cb(false); };
        xhr.send(formData);
    }

    function uploadMultipart(idx, file, cb) {
        var objectName = file.name;
        var contentType = file.type || 'application/octet-stream';
        var chunkSize   = CHUNK_SIZE;
        var totalChunks = Math.ceil(file.size / chunkSize);
        var resume      = file._resumeRecord;

        if (resume && resume.uploadId) {
            var doneParts = (resume.completedParts || []).map(function(p) { return { partNum: p.partNum, etag: p.etag }; });
            var doneNums  = doneParts.map(function(p) { return p.partNum; });
            var nextPart  = 1;
            while (doneNums.indexOf(nextPart) !== -1) nextPart++;
            _activeUploadId = { tenantId: currentTenantId, namespace: currentNamespace, bucketName: currentBucketName, objectName: objectName, uploadId: resume.uploadId };
            setFilePct(idx, I18N.uploadResuming);
            uploadChunks(idx, file, resume.uploadId, objectName, totalChunks, doneParts, nextPart, cb);
        } else {
            postJson('/oci/storage/object/multipart/initiate', {
                tenantId: currentTenantId,
                namespace: currentNamespace,
                bucketName: currentBucketName,
                objectName: objectName,
                contentType: contentType,
                totalSize: file.size,
                chunkSize: chunkSize
            }).then(function(res) {
                if (!res.success) { cb(false); return; }
                var uploadId = res.data.uploadId;
                _activeUploadId = { tenantId: currentTenantId, namespace: currentNamespace, bucketName: currentBucketName, objectName: objectName, uploadId: uploadId };
                uploadChunks(idx, file, uploadId, objectName, totalChunks, [], 1, cb);
            }).catch(function() { cb(false); });
        }
    }

    function uploadChunks(idx, file, uploadId, objectName, totalChunks, parts, partNum, cb) {
        if (_uploadAborted) {
            abortMultipart(_activeUploadId);
            return;
        }
        if (partNum > totalChunks) {
            postJson('/oci/storage/object/multipart/commit', {
                tenantId: currentTenantId,
                namespace: currentNamespace,
                bucketName: currentBucketName,
                objectName: objectName,
                uploadId: uploadId,
                parts: parts
            }).then(function(res) {
                if (res.success) {
                    setFileBar(idx, 100);
                    setFilePct(idx, I18N.uploadDone, 'var(--accent-g)');
                    _activeUploadId = null;
                    cb(true);
                } else {
                    cb(false);
                }
            }).catch(function() { cb(false); });
            return;
        }

        var start = (partNum - 1) * CHUNK_SIZE;
        var end   = Math.min(start + CHUNK_SIZE, file.size);
        var chunk = file.slice(start, end);

        var formData = new FormData();
        formData.append('tenantId', currentTenantId);
        formData.append('namespace', currentNamespace);
        formData.append('bucketName', currentBucketName);
        formData.append('objectName', objectName);
        formData.append('uploadId', uploadId);
        formData.append('partNumber', partNum);
        formData.append('chunk', chunk, 'part-' + partNum);

        var xhr = new XMLHttpRequest();
        _activeXhr = xhr;
        xhr.open('POST', '/oci/storage/object/multipart/part');
        xhr.setRequestHeader('X-CSRF-TOKEN', getCsrf());

        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                var partDone = (partNum - 1) / totalChunks;
                var partPct  = e.loaded / e.total / totalChunks;
                var overall  = Math.round((partDone + partPct) * 100);
                setFileBar(idx, overall);
                setFilePct(idx, overall + '% (' + partNum + '/' + totalChunks + ' 片)');
                updateOverallProgress();
            }
        };
        xhr.onload = function() {
            try {
                var res = JSON.parse(xhr.responseText);
                if (res.success) {
                    parts.push({ partNum: partNum, etag: res.data.etag });
                    uploadChunks(idx, file, uploadId, objectName, totalChunks, parts, partNum + 1, cb);
                } else {
                    cb(false);
                }
            } catch(e) { cb(false); }
        };
        xhr.onerror = function() { cb(false); };
        xhr.send(formData);
    }

    function abortMultipart(info) {
        if (!info) return;
        postJson('/oci/storage/object/multipart/abort', info).catch(function(){});
        _activeUploadId = null;
    }

    function setFileBar(idx, pct) {
        var bar = document.getElementById('upload-bar-' + idx);
        if (bar) bar.style.width = pct + '%';
    }

    function setFilePct(idx, text, color) {
        var el = document.getElementById('upload-pct-' + idx);
        if (el) { el.textContent = text; if (color) el.style.color = color; }
    }

    function setOverallProgress(pct) {
        document.getElementById('uploadOverallBar').style.width = pct + '%';
        document.getElementById('uploadOverallPct').textContent = pct + '%';
    }

    function updateOverallProgress() {
        var bars = document.querySelectorAll('[id^="upload-bar-"]');
        var total = 0;
        bars.forEach(function(b) { total += parseFloat(b.style.width) || 0; });
        var pct = Math.round(total / bars.length);
        setOverallProgress(pct);
    }

    function cancelUpload() {
        _uploadAborted = true;
        if (_activeXhr) { _activeXhr.abort(); _activeXhr = null; }
        if (_activeUploadId) { abortMultipart(_activeUploadId); }
        closeUploadModal();
    }

    function closeUploadModal() {
        document.getElementById('uploadProgressModal').classList.remove('active');
    }

    /* ============================================================
       Download
    ============================================================ */
    function downloadObject(objectName) {
        var params = new URLSearchParams({
            tenantId: currentTenantId,
            namespace: currentNamespace,
            bucketName: currentBucketName,
            objectName: objectName
        });
        window.location.href = '/oci/storage/object/download?' + params.toString();
    }

    /* ============================================================
       Preview
    ============================================================ */
    var PREVIEW_EXTS = ['png','jpg','jpeg','gif','webp','svg','pdf','txt','log','md','json','xml','html','htm'];

    function isPreviewable(name) {
        var ext = name.split('.').pop().toLowerCase();
        return PREVIEW_EXTS.indexOf(ext) !== -1;
    }

    function previewObject(objectName) {
        var params = new URLSearchParams({
            tenantId: currentTenantId,
            namespace: currentNamespace,
            bucketName: currentBucketName,
            objectName: objectName
        });
        var url = '/oci/storage/object/preview?' + params.toString();
        var ext = objectName.split('.').pop().toLowerCase();
        var isImage = ['png','jpg','jpeg','gif','webp','svg'].indexOf(ext) !== -1;
        var isPdf   = ext === 'pdf';

        if (isImage) {
            Swal.fire({
                title: objectName.split('/').pop(),
                imageUrl: url,
                imageAlt: objectName,
                width: '80vw',
                confirmButtonText: I18N.btnClose,
                showDenyButton: true,
                denyButtonText: '<i class="fas fa-download"></i> ' + I18N.btnDownload,
                denyButtonColor: '#768390'
            }).then(r => { if (r.isDenied) downloadObject(objectName); });
        } else if (isPdf) {
            window.open(url, '_blank');
        } else {
            fetch(url, { headers: { 'X-CSRF-TOKEN': getCsrf() } })
                .then(r => r.text())
                .then(text => {
                    Swal.fire({
                        title: objectName.split('/').pop(),
                        html: '<pre style="text-align:left;max-height:60vh;overflow:auto;font-size:12px;white-space:pre-wrap;word-break:break-all;">' + escHtml(text) + '</pre>',
                        width: '70vw',
                        confirmButtonText: I18N.btnClose,
                        showDenyButton: true,
                        denyButtonText: '<i class="fas fa-download"></i> ' + I18N.btnDownload,
                        denyButtonColor: '#768390'
                    }).then(r => { if (r.isDenied) downloadObject(objectName); });
                })
                .catch(() => {
                    Swal.fire({ icon: 'error', title: I18N.previewFail, text: I18N.previewLoadFail });
                });
        }
    }
</script>
</body>
</html>