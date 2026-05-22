function showSuccessMessage(message) {
    const successAlert = document.getElementById('successAlert');
    const successMessage = document.getElementById('successMessage');
    successMessage.textContent = message;
    successAlert.style.display = 'flex';

    hideErrorMessage();
}

function showErrorMessage(message) {
    const errorAlert = document.getElementById('errorAlert');
    const errorMessage = document.getElementById('errorMessage');
    errorMessage.textContent = message;
    errorAlert.style.display = 'flex';
}

function hideErrorMessage() {
    document.getElementById('errorAlert').style.display = 'none';
}

function getCsrfTokenFromMetaOrInput() {
    const csrfMeta = document.querySelector('meta[name="_csrf"]');
    if (csrfMeta) return csrfMeta.getAttribute('content');
    const csrfInput = document.querySelector('input[name="_csrf"]');
    if (csrfInput) return csrfInput.value;
    return null;
}

function getCsrfHeaderName() {
    const headerMeta = document.querySelector('meta[name="_csrf_header"]');
    if (headerMeta) return headerMeta.getAttribute('content');
    return 'X-CSRF-TOKEN';
}

document.addEventListener('DOMContentLoaded', function () {
    const i18n = window.migrationI18n || {};
    const btnExportEncrypted = document.getElementById("btnExportEncrypted");
    const btnImport = document.getElementById("btnImport");
    const fileInput = document.getElementById("sqlFileInput");
    const fileLabel = document.getElementById("fileDropArea"); // 这里用你的 label id
    const fileLabelText = document.getElementById("fileLabelText");
    const masterKeyGroup = document.getElementById("masterKeyGroup");
    const masterKeyInput = document.getElementById("masterKeyInput");


    document.querySelectorAll('input[name="importMode"]').forEach(radio => {
        radio.addEventListener('change', function () {
            const mode = this.value;
            if (mode === 'plain') {
                masterKeyGroup.style.display = 'none';
                fileInput.value = "";
                fileInput.setAttribute('accept', '.sql');
                fileLabelText.textContent = i18n.dragTipSql || "Select .sql file...";
            } else {
                masterKeyGroup.style.display = 'block';
                fileInput.value = "";
                fileInput.setAttribute('accept', '.enc');
                fileLabelText.textContent = i18n.dragTipEnc || "Select .enc file...";
            }
        });
    });

    btnExportEncrypted.addEventListener("click", async function () {
        hideErrorMessage();
        showSuccessMessage(i18n.exporting);

        try {
            const resp = await fetch("/migration/exportEncrypted", {
                method: "GET",
                headers: {
                    [getCsrfHeaderName()]: getCsrfTokenFromMetaOrInput() || ''
                }
            });

            if (!resp.ok) {
                throw new Error(i18n.exportFail + " HTTP " + resp.status);
            }

            const masterKey = resp.headers.get("X-MASTER-KEY");

            const blob = await resp.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = "oci-start_migration_" + Date.now() + ".enc";
            document.body.appendChild(a);
            a.click();
            a.remove();

            if (typeof Swal !== "undefined" && masterKey) {
                await Swal.fire({
                    icon: "info",
                    title: i18n.swalTitle,
                    html:
                        `<div style="font-size:13px; margin-bottom:8px; text-align:left;">
                           <p>${i18n.swalFileGenerated || 'Backup generated: .enc'}</p>
                           <p style="color:#e74c3c;font-weight:600;">${i18n.swalDesc}</p>
                         </div>
                         <div style="padding:8px 10px; border:1px dashed #ddd; border-radius:4px; background:#fafafa; word-break:break-all; font-family:monospace;">
                           ${masterKey}
                         </div>`,
                    confirmButtonText: i18n.swalBtn,
                    allowOutsideClick: false
                });
            } else {
                showSuccessMessage(i18n.exportSuccess);
            }

        } catch (e) {
            console.error(e);
            showErrorMessage(i18n.exportFail + e.message);
        }
    });

    btnImport.addEventListener("click", async function () {
        hideErrorMessage();

        const mode = document.querySelector('input[name="importMode"]:checked').value;

        if (!fileInput.files.length) {
            showErrorMessage(i18n.noFile);
            return;
        }

        if (mode === 'encrypted' && !masterKeyInput.value.trim()) {
            showErrorMessage(i18n.noSecret);
            masterKeyInput.focus();
            return;
        }

        const formData = new FormData();
        formData.append("file", fileInput.files[0]);

        let url = "/migration/import";
        if (mode === 'encrypted') {
            url = "/migration/importEncrypted";
            formData.append("masterKey", masterKeyInput.value.trim());
        }

        showSuccessMessage(i18n.importing);

        try {
            const csrfToken = getCsrfTokenFromMetaOrInput();
            const csrfHeader = getCsrfHeaderName();

            const resp = await fetch(url, {
                method: "POST",
                body: formData,
                headers: csrfToken ? { [csrfHeader]: csrfToken } : {}
            });

            const text = await resp.text();

            if (resp.ok && text && text.indexOf("成功") !== -1) {
                showSuccessMessage(i18n.importSuccess);
            } else {
                showErrorMessage(i18n.importFail + text);
            }

        } catch (err) {
            console.error(err);
            showErrorMessage(i18n.importFail + err.message);
        }
    });

    // ================== 文件拖拽支持 =====================
    // 使用你页面上的 label id：fileDropArea
    fileLabel.addEventListener("dragover", e => {
        e.preventDefault();
        fileLabel.classList.add("drag-active");
    });

    fileLabel.addEventListener("dragleave", e => {
        e.preventDefault();
        fileLabel.classList.remove("drag-active");
    });

    fileLabel.addEventListener("drop", e => {
        e.preventDefault();
        fileLabel.classList.remove("drag-active");

        const file = e.dataTransfer.files[0];
        if (!file) return;

        const mode = document.querySelector('input[name="importMode"]:checked').value;
        const expectExt = mode === 'plain' ? '.sql' : '.enc';

        if (!file.name.toLowerCase().endsWith(expectExt)) {
            showErrorMessage(i18n.importFail + " " + expectExt);
            return;
        }

        const dt = new DataTransfer();
        dt.items.add(file);
        fileInput.files = dt.files;

        fileLabelText.textContent = "已选择文件：" + file.name;
    });

    // 普通选择文件时更新文案
    fileInput.addEventListener("change", function (e) {
        const file = e.target.files[0];
        if (file) {
            fileLabelText.textContent = "已选择文件：" + file.name;
        } else {
            const mode = document.querySelector('input[name="importMode"]:checked').value;
            fileLabelText.textContent = mode === 'plain'
                ? "点击选择 SQL 文件 或 直接拖拽 .sql 文件到这里"
                : "点击选择加密文件(.enc) 或 直接拖拽 .enc 文件到这里";
        }
    });

    // ================== 侧边栏展开逻辑（保持和其他页面一致） =====================
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        if (!parentLink) return;
        parentLink.addEventListener('click', (e) => {
            e.preventDefault();
            parent.classList.toggle('expanded');
        });
    });

    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }
});

document.addEventListener('DOMContentLoaded', () => {
    // 1. 默认选中导入模式：encrypted
    const defaultRadio = document.querySelector('input[name="importMode"][value="encrypted"]');
    if (defaultRadio) {
        defaultRadio.checked = true;
    }

    // 2. 显示 Master Key 输入框
    const masterKeyGroup = document.getElementById('masterKeyGroup');
    if (masterKeyGroup) {
        masterKeyGroup.style.display = 'block';
    }

});

