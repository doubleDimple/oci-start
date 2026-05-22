
let currentCloudType = 1;
const providerLogoMap = {
    1: '/images/oracle.png',
    2: '/images/google.png',
    3: '/images/aws.png',
    4: '/images/azure.png'
};
const i18n = window.I18N;
// 页面加载时初始化
document.addEventListener('DOMContentLoaded', function() {
    // 从header.ftl获取当前云厂商类型
    if (typeof getCurrentProviderType === 'function') {
        currentCloudType = getCurrentProviderType();
        // 根据当前云厂商初始化页面
        const providerInfo = getCurrentProviderInfo();
        switchCloudProvider(providerInfo.type, providerInfo.name, providerInfo.logo);
    } else {
        // 如果header还没加载完成，设置默认值
        setDefaultProvider();
    }

    // 监听云厂商变更事件（来自header.ftl）
    document.addEventListener('cloudProviderChanged', function(event) {
        const providerType = event.detail.type;
        const providerName = event.detail.name;
        const providerLogo = event.detail.logo;

        currentCloudType = providerType;
        switchCloudProvider(providerType, providerName, providerLogo);
    });

    // 初始化侧边栏
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        parentLink.addEventListener('click', (e) => {
            e.preventDefault();
            parent.classList.toggle('expanded');
        });
    });

    // 展开当前活动菜单
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }

    setupDragDropHandlers();
});

function setDefaultProvider() {
    currentCloudType = 1;
    switchCloudProvider(1, 'Oracle Cloud', '/images/oracle.png');
}

// 切换云厂商
function switchCloudProvider(type, name, logo) {
    document.getElementById('currentProviderLogo').src = providerLogoMap[type];
    document.getElementById('currentProviderName').textContent = name;
    document.getElementById('cloudType').value = type;

    updateFieldLabels(type);
    updateRegionOptions(type);
    updateConfigPlaceholder(type === 1 ? 'oracle' : 'gcp');
    clearForm();
}

// 更新字段标签和显示
function updateFieldLabels(cloudType) {
    const tenantIdLabel = document.getElementById('tenantIdLabel');
    const fingerprintLabel = document.getElementById('fingerprintLabel');
    const tenancyLabel = document.getElementById('tenancyLabel');
    const regionGroup = document.getElementById('regionGroup');
    const regionSelect = document.getElementById('region');
    const fileInputWrapper = document.querySelector('.file-input-wrapper');
    const fileLabel = document.querySelector('.file-input-label span');

    if (cloudType === 1) { // Oracle Cloud
        tenantIdLabel.textContent = 'User(API user)';
        fingerprintLabel.textContent = 'Fingerprint(API fingerprint)';
        tenancyLabel.textContent = 'Tenancy(API tenancy)';

        // 显示 region 字段
        regionGroup.style.display = 'block';
        regionSelect.required = true;
        fileLabel.textContent = i18n.tenant_selectFile;
        fileLabel.style.color = '';
        fileLabel.style.fontWeight = '';

    } else if (cloudType === 2) { // Google Cloud
        tenantIdLabel.textContent = 'Client Email';
        fingerprintLabel.textContent = 'Private Key ID';
        tenancyLabel.textContent = 'Project ID';

        // 隐藏 region 字段，GCP 不需要在 API 凭据中指定 region
        regionGroup.style.display = 'none';
        regionSelect.required = false;
        regionSelect.value = '';
        fileLabel.textContent = i18n.speedadd_json;
        fileLabel.style.color = '#666';
    }
}

function updateRegionOptions(cloudType) {
    const oracleRegions = document.getElementById('oracleRegions');
    const regionSelect = document.getElementById('region');

    if (cloudType === 1) { // Oracle Cloud
        oracleRegions.style.display = '';
    }

    // 重置选择
    regionSelect.value = '';
}

// 更新配置文本框提示
function updateConfigPlaceholder(provider) {
    const configInput = document.getElementById('configInput');
    if (provider === 'oracle') {
        configInput.placeholder = i18n.speedadd_ociJson+`：
[DEFAULT]
user=ocid1.user.oc1..example
fingerprint=xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..example
region=us-phoenix-1`;
    } else if (provider === 'gcp') {
        configInput.placeholder = i18n.speedadd_gcpJson+`：
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n",
  "client_email": "service-account@project.iam.gserviceaccount.com"
}`;
    }
}

// 清空表单
function clearForm() {
    const form = document.getElementById('apiForm');
    const inputs = form.querySelectorAll('input[type="text"], select, textarea');
    inputs.forEach(input => {
        if (input.id !== 'cloudType' && input.id !== 'status') {
            input.value = '';
            input.classList.remove('error');
        }
    });

    // 重置文件输入
    const fileInput = document.getElementById('keyFileStr');
    fileInput.value = '';
    const fileLabel = fileInput.previousElementSibling.querySelector('span');

    // 根据当前云厂商类型重置文件输入显示
    if (currentCloudType === 1) {
        fileLabel.textContent = i18n.tenant_selectFile;
    } else if (currentCloudType === 2) {
        fileLabel.textContent = i18n.speedadd_json;
    }
    fileLabel.style.color = '';
    fileLabel.style.fontWeight = '';

    // 清空配置文本框
    document.getElementById('configInput').value = '';

    hideErrorMessage();
    hideSuccessMessage();
}

// 处理配置文本解析
document.getElementById('configInput').addEventListener('input', function(e) {
    const configText = e.target.value;
    if (!configText.trim()) return;

    try {
        if (currentCloudType === 1) {
            // Oracle Cloud配置解析
            parseOracleConfig(configText);
        } else if (currentCloudType === 2) {
            // GCP配置解析
            parseGcpConfig(configText);
        }
    } catch (error) {
        showErrorMessage(i18n.speedadd_errorJson);
    }
});

// 解析Oracle Cloud配置
function parseOracleConfig(configText) {
    const lines = configText.split('\n');
    const data = {};
    let currentSection = '';

    lines.forEach(line => {
        line = line.trim();
        // 检查是否是节标题行 [xxxx]
        if (line.startsWith('[') && line.endsWith(']')) {
            currentSection = line.substring(1, line.length - 1);
            return;
        }

        if (line.includes('=')) {
            const [key, value] = line.split('=').map(s => s.trim());
            data[key.toLowerCase()] = value;
            if (currentSection) {
                data['section'] = currentSection;
            }
        }
    });

    // 填充表单 - 使用复用字段
    if (data.section) {
        document.getElementById('userName').value = data.section;
    }
    if (data.user) {
        document.getElementById('tenantId').value = data.user;
    }
    if (data.fingerprint) {
        document.getElementById('fingerprint').value = data.fingerprint;
    }
    if (data.tenancy) {
        document.getElementById('tenancy').value = data.tenancy; // 复用为Oracle Tenancy
    }
    if (data.region) {
        const regionSelect = document.getElementById('region');
        // 查找Oracle区域选项
        const oracleRegions = document.querySelectorAll('#oracleRegions option');
        const regionOption = Array.from(oracleRegions).find(option =>
            option.value === data.region
        );
        if (regionOption) {
            regionSelect.value = data.region; // 复用为Oracle Region
            showSuccessMessage(i18n.speedadd_ociJsonSucc);
        } else {
            showErrorMessage(i18n.speedadd_ociJsonnoFund);
        }
    }

    hideErrorMessage();
}

// 解析GCP配置
function parseGcpConfig(configText) {
    try {
        const config = JSON.parse(configText);

        // 验证是否为有效的GCP服务账号配置
        if (config.type !== 'service_account') {
            showErrorMessage(i18n.speedadd_gcpJsonnoFund);
            return;
        }

        // 填充表单 - 使用复用字段
        if (config.project_id) {
            document.getElementById('tenancy').value = config.project_id; // 复用为GCP Project ID
            document.getElementById('userName').value = config.project_id; // 使用项目ID作为用户名
        }
        if (config.client_email) {
            document.getElementById('tenantId').value = config.client_email; // 复用为GCP Client Email
        }
        if (config.private_key_id) {
            document.getElementById('fingerprint').value = config.private_key_id; // 复用为GCP Private Key ID
        }

        // 创建一个文件名
        let fileName = 'gcp-service-account.json'; // 默认名称
        if (config.project_id) {
            fileName = config.project_id + `-service-account.json`;
        } else if (config.client_id) {
            fileName = config.client_id +`-service-account.json`;
        } else {
            // 如果都没有，使用时间戳确保唯一性
            const timestamp = new Date().getTime();
            fileName = `gcp-service-account-`+ timestamp+`.json`;
        }

        // 保存原始的配置文本，而不是重新生成
        const jsonBlob = new Blob([configText], { type: 'application/json' });
        const virtualFile = new File([jsonBlob], fileName, { type: 'application/json' });

        // 设置文件到文件输入框
        const fileInput = document.getElementById('keyFileStr');
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(virtualFile);
        fileInput.files = dataTransfer.files;

        // 更新文件名显示
        const fileLabel = fileInput.previousElementSibling.querySelector('span');
        fileLabel.textContent = `✅ `+fileName ;
        fileLabel.style.color = '#2ecc71';
        fileLabel.style.fontWeight = '500';

        showSuccessMessage(i18n.speedadd_gcpJsonnoSucc);
        hideErrorMessage();
    } catch (error) {
        showErrorMessage(i18n.speedadd_gcpJsonnoError);
    }
}

// 文件上传预览
document.getElementById('keyFileStr').addEventListener('change', function(e) {
    const fileName = e.target.files[0]?.name;
    if (fileName) {
        this.previousElementSibling.querySelector('span').textContent = fileName;
    }
});
bindFormSubmit("apiForm", {
    url: "/tenants/save",
    method: "POST",
    required: ["userName", "keyFileStr"],
    extraRequiredByCloudType: {
        1: ["tenantId", "fingerprint", "tenancy", "region"], // OCI
        2: ["tenantId", "fingerprint", "tenancy"]            // GCP
    },
    redirect: "/tenants/list",
    loading: true,
    loadingText: i18n.speedadd_waitCommit,
    showSuccess: true,
    showError: true
});


// 设置拖拽处理程序
function setupDragDropHandlers() {
    const configInput = document.getElementById('configInput');
    const wrapper = configInput.closest('.config-textarea-wrapper');
    const fileInput = document.getElementById('keyFileStr');

    // 处理文件
    function handleFile(file) {
        const fileName = file.name.toLowerCase();

        if (currentCloudType === 1 && fileName.endsWith('.pem')) {
            // Oracle Cloud .pem文件
            setFileToInput(file, fileInput);
            showSuccessMessage('successful');
        } else if (currentCloudType === 2 && fileName.endsWith('.json')) {
            // GCP .json文件 - 直接使用原始文件
            setFileToInput(file, fileInput);

            // 读取JSON文件内容并解析以填充表单字段
            const reader = new FileReader();
            reader.onload = function(e) {
                try {
                    const content = e.target.result;
                    configInput.value = content;
                    parseGcpConfig(content);
                } catch (error) {
                    showErrorMessage('JSON文件读取失败');
                }
            };
            reader.readAsText(file);

            showSuccessMessage('successful');
        } else {
            const expectedExt = currentCloudType === 1 ? '.pem' : '.json';
            const providerName = currentCloudType === 1 ? 'Oracle Cloud' : 'GCP';
            showErrorMessage(i18n.openBoot_select``+expectedExt +`（` + providerName+`）`);
        }
    }

    // 设置文件到文件输入框 - 直接使用原始文件
    function setFileToInput(file, inputElement) {
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        inputElement.files = dataTransfer.files;

        // 更新文件名显示
        const fileLabel = inputElement.previousElementSibling.querySelector('span');
        fileLabel.textContent = file.name;
    }

    // 拖放事件处理
    configInput.addEventListener('dragenter', (e) => {
        e.preventDefault();
        wrapper.classList.add('drag-active');
    });

    configInput.addEventListener('dragover', (e) => {
        e.preventDefault();
        wrapper.classList.add('drag-active');
    });

    configInput.addEventListener('dragleave', (e) => {
        e.preventDefault();
        wrapper.classList.remove('drag-active');
    });

    configInput.addEventListener('drop', (e) => {
        e.preventDefault();
        wrapper.classList.remove('drag-active');

        const file = e.dataTransfer.files[0];
        handleFile(file);
    });

    // 粘贴事件处理
    configInput.addEventListener('paste', (e) => {
        const clipboardData = e.clipboardData || window.clipboardData;
        const items = clipboardData.items;

        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item.kind === 'file') {
                e.preventDefault();
                const file = item.getAsFile();
                handleFile(file);
                break;
            }
        }
    });
}

// 消息显示函数
function showErrorMessage(message) {
    const errorAlert = document.getElementById('errorAlert');
    const errorMessage = document.getElementById('errorMessage');
    errorMessage.textContent = message;
    errorAlert.style.display = 'flex';
    hideSuccessMessage();
}

function hideErrorMessage() {
    document.getElementById('errorAlert').style.display = 'none';
}

function showSuccessMessage(message) {
    const successAlert = document.getElementById('successAlert');
    const successMessage = document.getElementById('successMessage');
    successMessage.textContent = message;
    successAlert.style.display = 'flex';
    hideErrorMessage();
}

function hideSuccessMessage() {
    document.getElementById('successAlert').style.display = 'none';
}

// 清除表单错误状态
document.querySelectorAll('.form-control').forEach(input => {
    input.addEventListener('input', function() {
        this.classList.remove('error');
        hideErrorMessage();
    });
});
