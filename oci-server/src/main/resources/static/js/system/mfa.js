let csrfToken, csrfHeaderName;

// Global variables
let globalUpdateTimer = null;
let isUpdatingOtp = false;

let i18n = {};

// Initialize page
document.addEventListener('DOMContentLoaded', function() {
    i18n = window.mfaI18n || {};
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    initMenuBehavior();
    initFileUpload();
    initFormSubmission();
    startOTPUpdates();
    updateTotalCount();
});

// Menu behavior
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

    // Expand current active menu
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }
}

// File upload handling
function initFileUpload() {
    const fileInput = document.getElementById('qrCode');
    const fileName = document.getElementById('fileName');
    const previewImage = document.getElementById('previewImage');
    const secretKeyInput = document.getElementById('secretKey');
    const pasteArea = document.getElementById('pasteArea');
    const uploadArea = document.getElementById('uploadArea');

    // File input change
    fileInput.addEventListener('change', function(e) {
        const file = e.target.files[0];
        if (file) {
            fileName.textContent = i18n.selected + `: ` + file.name;
            fileName.style.color = 'var(--accent-green)';
            const reader = new FileReader();
            reader.onload = function(e) {
                previewImage.src = e.target.result;
                previewImage.style.display = 'block';
            }
            reader.readAsDataURL(file);
            secretKeyInput.value = '';
            secretKeyInput.readOnly = true;
            secretKeyInput.placeholder = i18n.autoExtract;
        } else {
            fileName.textContent = i18n.noFile;
            fileName.style.color = 'var(--text-secondary)';
            previewImage.style.display = 'none';
            secretKeyInput.readOnly = false;
            secretKeyInput.placeholder = i18n.placeholderSecret;
        }
    });

    // Drag and drop
    uploadArea.addEventListener('dragover', function(e) {
        e.preventDefault();
        uploadArea.classList.add('dragover');
    });

    uploadArea.addEventListener('dragleave', function(e) {
        e.preventDefault();
        uploadArea.classList.remove('dragover');
    });

    uploadArea.addEventListener('drop', function(e) {
        e.preventDefault();
        uploadArea.classList.remove('dragover');
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            const container = new DataTransfer();
            container.items.add(files[0]);
            fileInput.files = container.files;
            fileInput.dispatchEvent(new Event('change'));
        }
    });

    // Paste functionality
    document.addEventListener('paste', function(e) {
        const items = e.clipboardData.items;
        for (let i = 0; i < items.length; i++) {
            if (items[i].type.indexOf('image') !== -1) {
                const file = items[i].getAsFile();
                const container = new DataTransfer();
                container.items.add(file);
                fileInput.files = container.files;
                fileInput.dispatchEvent(new Event('change'));
                e.preventDefault();
                break;
            }
        }
    });

    pasteArea.addEventListener('click', function() {
        fileInput.click();
    });
}

// Form submission with SweetAlert2
function initFormSubmission() {
    const form = document.getElementById('keyForm');
    form.addEventListener('submit', function(e) {
        const keyName = document.getElementById('keyName').value.trim();
        const secretKey = document.getElementById('secretKey').value.trim();
        const fileInput = document.getElementById('qrCode');

        if (!keyName) {
            e.preventDefault();
            Swal.fire({
                icon: 'warning',
                title: i18n.requireName,
                //text: '密钥名称不能为空',
                confirmButtonColor: '#1abc9c'
            });
            return;
        }

        if (!secretKey && !fileInput.files[0]) {
            e.preventDefault();
            Swal.fire({
                icon: 'warning',
                title: i18n.requireSecret, // '请输入密钥内容'
                //text: '请输入密钥内容或上传二维码',
                confirmButtonColor: '#1abc9c'
            });
            return;
        }

        // Show loading state
        const submitBtn = form.querySelector('button[type="submit"]');
        const originalHTML = submitBtn.innerHTML;
        submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+ i18n.saving;
        submitBtn.disabled = true;
        setTimeout(() => {
            submitBtn.innerHTML = originalHTML;
            submitBtn.disabled = false;
        }, 10000);
    });

    // Reset form
    const resetBtn = form.querySelector('button[type="reset"]');
    if (resetBtn) {
        resetBtn.addEventListener('click', function() {
            document.getElementById('fileName').textContent = '未选择文件';
            document.getElementById('fileName').style.color = 'var(--text-secondary)';
            document.getElementById('previewImage').style.display = 'none';
            document.getElementById('secretKey').readOnly = false;
            document.getElementById('secretKey').placeholder = '请输入密钥或上传二维码';
        });
    }
}

// Start OTP updates
function startOTPUpdates() {
    updateOTPCodes();
    updateCountdown();

    if (globalUpdateTimer) {
        clearInterval(globalUpdateTimer);
    }

    globalUpdateTimer = setInterval(() => {
        updateCountdown();
        const timeLeft = 30 - (Math.floor(Date.now() / 1000) % 30);
        if (timeLeft === 30 && !isUpdatingOtp) {
            updateOTPCodes();
        }
    }, 1000);
}

// Update countdown
function updateCountdown() {
    const timeLeft = 30 - (Math.floor(Date.now() / 1000) % 30);
    const countdownElements = document.querySelectorAll('.countdown-badge');

    countdownElements.forEach(element => {
        element.textContent = timeLeft;
        element.className = 'countdown-badge';
        if (timeLeft <= 5) {
            element.classList.add('danger');
        } else if (timeLeft <= 10) {
            element.classList.add('warning');
        }
    });
}

// Update OTP codes
async function updateOTPCodes() {
    if (isUpdatingOtp) return;
    isUpdatingOtp = true;

    const otpElements = document.querySelectorAll('.otp-code-display[data-secret]');
    if (otpElements.length === 0) {
        isUpdatingOtp = false;
        return;
    }

    // Collect secret keys
    const secretKeys = Array.from(otpElements)
        .map(element => element.getAttribute('data-secret'))
        .filter(key => key && key.trim() !== '');

    if (secretKeys.length === 0) {
        isUpdatingOtp = false;
        return;
    }

    try {
        //const csrfToken = document.querySelector('input[name="${_csrf.parameterName}"]').value;
        const response = await fetch('/generate-otp-batch', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({ secretKeys })
        });

        if (!response.ok) {
            throw new Error('Network response was not ok');
        }

        const otpResponses = await response.json();
        const otpMap = new Map(
            otpResponses.map(response => [response.secretKey, response.otpCode])
        );

        // Update displays
        otpElements.forEach(element => {
            const secretKey = element.getAttribute('data-secret');
            if (otpMap.has(secretKey)) {
                element.textContent = otpMap.get(secretKey);
                element.classList.remove('loading');
            }
        });

    } catch (error) {
        console.error('Error updating OTP codes:', error);
        otpElements.forEach(element => {
            element.textContent = 'Error';
            element.classList.remove('loading');
        });
    } finally {
        isUpdatingOtp = false;
    }
}

// Toggle secret display - 优化的密钥显示功能
function toggleSecretDisplay(element) {
    const secret = element.getAttribute('data-secret');
    const isRevealed = element.classList.contains('revealed');

    if (isRevealed) {
        // 如果已显示，点击复制
        copyToClipboard(secret);
    } else {
        // 显示密钥
        element.innerHTML = `
                <span>`+secret +`</span>
                <i class="fas fa-copy secret-copy-icon"></i>
            `;
        element.classList.add('revealed');
        element.setAttribute('data-tooltip', i18n.clickCopy);

        // 5秒后自动隐藏
        setTimeout(() => {
            if (element.classList.contains('revealed')) {
                hideSecret(element);
            }
        }, 5000);
    }
}

// Hide secret
function hideSecret(element) {
    element.innerHTML = `
            <span class="secret-hidden">••••••••••••</span>
            <i class="fas fa-eye secret-copy-icon"></i>
        `;
    element.classList.remove('revealed');
    element.setAttribute('data-tooltip', i18n.clickShow);
}

// Search functionality
function searchKeys() {
    const searchTerm = document.getElementById('searchInput').value.toLowerCase();
    const keyRows = document.querySelectorAll('.key-row');
    let visibleCount = 0;

    keyRows.forEach(row => {
        const keyName = row.getAttribute('data-key-name').toLowerCase();
        const issuer = row.getAttribute('data-issuer').toLowerCase();

        const shouldShow = keyName.includes(searchTerm) || issuer.includes(searchTerm);
        row.style.display = shouldShow ? '' : 'none';

        if (shouldShow) {
            visibleCount++;
        }
    });

    document.getElementById('totalCount').textContent = visibleCount;
}

// Update total count
function updateTotalCount() {
    const totalKeys = document.querySelectorAll('.key-row').length;
    document.getElementById('totalCount').textContent = totalKeys;
}

// Export data
function exportData() {
    try {
        const rows = [];
        const headers = ['密钥名称', '发行者', '密钥内容'];
        rows.push(headers);

        document.querySelectorAll('.key-row:not([style*="display: none"])').forEach(row => {
            const keyName = row.querySelector('.key-name-cell')?.textContent.trim() || '';
            const issuer = row.querySelector('.issuer-badge')?.textContent.trim() || '';
            const secretKey = row.querySelector('.secret-display')?.getAttribute('data-secret') || '';

            rows.push([keyName, issuer, secretKey]);
        });

        const csvContent = rows
            .map(row => row.map(cell => {
                if (cell == null) return '';
                cell = cell.toString();
                if (cell.includes(',') || cell.includes('"') || cell.includes('\n')) {
                    cell = cell.replace(/"/g, '""');
                    cell = '"' + cell + '"';
                }
                return cell;
            }).join(','))
            .join('\n');

        const blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;

        const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '');
        a.download = `mfa_keys_export_`+ timestamp+`.csv`;

        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);

        showToast('数据导出成功！');
    } catch (error) {
        console.error('Export failed:', error);
        Swal.fire({
            icon: 'error',
            title: '导出失败',
            text: '导出过程中出现错误，请重试',
            confirmButtonColor: '#ff6b6b'
        });
    }
}

async function deleteKey(keyName) {
    const result = await Swal.fire({
        title: i18n.confirmDeleteTitle,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.btnConfirm,
        cancelButtonText: i18n.btnCancel,
        reverseButtons: true,
        focusCancel: true
    });

    if (!result.isConfirmed) {
        return;
    }

    // Show deleting progress
    Swal.fire({
        title: i18n.deleting,
        //text: '正在删除密钥',
        icon: 'info',
        allowOutsideClick: false,
        showConfirmButton: false,
        didOpen: function() {
            Swal.showLoading();
        }
    });

    try {
        const response = await fetch('/delete-key', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({ keyName: keyName })
        });

        if (response.ok) {
            // 查找要删除的行
            var rows = document.querySelectorAll('.key-row');
            var targetRow = null;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].getAttribute('data-key-name') === keyName) {
                    targetRow = rows[i];
                    break;
                }
            }

            if (targetRow) {
                targetRow.style.transition = 'all 0.3s ease';
                targetRow.style.transform = 'translateX(-100%)';
                targetRow.style.opacity = '0';

                setTimeout(function() {
                    Swal.fire({
                        icon: 'success',
                        title: i18n.deleteSuccess,
                        confirmButtonColor: '#1abc9c',
                        timer: 2000,
                        timerProgressBar: true
                    }).then(function() {
                        location.reload();
                    });
                }, 300);
            } else {
                location.reload();
            }
        } else {
            throw new Error(i18n.deleteFail);
        }
    } catch (error) {
        console.error('Error deleting key:', error);
        Swal.fire({
            icon: 'error',
            title: i18n.deleteFail,
            confirmButtonColor: '#ff6b6b'
        });
    }
}

// Enlarge QR code
function enlargeQrCode(imgElement) {
    const modal = document.getElementById('qrModal');
    const modalImage = document.getElementById('modalImage');
    modalImage.src = imgElement.src;
    modal.style.display = 'flex';
}

// Close modal
function closeModal() {
    document.getElementById('qrModal').style.display = 'none';
}

// Close modal on outside click
window.addEventListener('click', function(e) {
    const modal = document.getElementById('qrModal');
    if (e.target === modal) {
        closeModal();
    }
});

// Close modal on ESC key
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeModal();
    }
});

// Copy to clipboard with better feedback
function copyToClipboard(text) {
    if (!text || text === i18n.loading || text === i18n.error) {
        return;
    }

    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
            Swal.fire({
                icon: 'success',
                title: i18n.copySuccess,
                //text: '密钥已复制到剪贴板',
                toast: true,
                position: 'top-end',
                showConfirmButton: false,
                timer: 2000,
                timerProgressBar: true
            });
        }).catch(err => {
            console.error('复制失败:', err);
            fallbackCopy(text);
        });
    } else {
        fallbackCopy(text);
    }
}

// Fallback copy method
function fallbackCopy(text) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-999999px';
    textArea.style.top = '-999999px';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    try {
        document.execCommand('copy');
        Swal.fire({
            icon: 'success',
            title: '复制成功！',
            text: '密钥已复制到剪贴板',
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 2000,
            timerProgressBar: true
        });
    } catch (err) {
        console.error('复制失败:', err);
        Swal.fire({
            icon: 'error',
            title: '复制失败',
            text: '请手动选择并复制密钥',
            confirmButtonColor: '#ff6b6b'
        });
    }

    document.body.removeChild(textArea);
}

// Show toast message
function showToast(message, type = 'success') {
    const existingToast = document.querySelector('.toast');
    if (existingToast) {
        existingToast.remove();
    }

    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;

    const bgColor = type === 'error' ? 'var(--accent-red)' : 'var(--accent-green)';
    toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: `+ bgColor+`;
            color: white;
            padding: 12px 20px;
            border-radius: 6px;
            font-size: 14px;
            z-index: 3000;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            animation: slideIn 0.3s ease;
        `;

    document.body.appendChild(toast);

    setTimeout(() => {
        toast.remove();
    }, 3000);
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (globalUpdateTimer) {
        clearInterval(globalUpdateTimer);
    }
});

// Auto-refresh prevention for session timeout
let lastActivity = Date.now();

document.addEventListener('click', () => {
    lastActivity = Date.now();
});

document.addEventListener('keypress', () => {
    lastActivity = Date.now();
});

// Check for inactivity every 5 minutes
setInterval(() => {
    const inactiveTime = Date.now() - lastActivity;
    if (inactiveTime > 30 * 60 * 1000) { // 30 minutes
        if (confirm('页面长时间未活动，是否刷新以保持会话？')) {
            location.reload();
        }
        lastActivity = Date.now();
    }
}, 5 * 60 * 1000);
