(() => {
let loadingStartTime = 0;

function showLoading(text = '正在加载中...') {
    loadingStartTime = Date.now();

    if (document.querySelector('.loading-overlay')) return;

    const overlay = document.createElement('div');
    overlay.className = 'loading-overlay';
    overlay.innerHTML = `
        <div class="loading-container">
            <div class="loading-spinner"></div>
            <div class="loading-text">${text}</div>
        </div>
    `;
    document.body.appendChild(overlay);
}

function hideLoading() {
    const overlay = document.querySelector('.loading-overlay');
    if (!overlay) return;

    const elapsed = Date.now() - loadingStartTime;
    const minDisplay = 600;

    const delay = elapsed < minDisplay ? minDisplay - elapsed : 0;
    setTimeout(() => overlay.remove(), delay);
}

function getCsrfToken() {
    const csrfInput = document.querySelector('input[name="_csrf"]');
    return csrfInput ? csrfInput.value : null;
}

function getCsrfHeader() {
    const csrfHeaderMeta = document.querySelector('meta[name="_csrf_header"]');
    return csrfHeaderMeta ? csrfHeaderMeta.getAttribute('content') : 'X-CSRF-TOKEN';
}

// ===============================================
//  通用超时封装
// ===============================================
const REQUEST_TIMEOUT = 10000;

function timeoutPromise(ms, promise) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("Request Timeout")), ms);
        promise.then(res => {
            clearTimeout(timer);
            resolve(res);
        }).catch(err => {
            clearTimeout(timer);
            reject(err);
        });
    });
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function pickMessage(payload, fallback = '请求失败，请稍后重试') {
    if (!payload) return fallback;
    if (typeof payload === 'string') return payload || fallback;
    return payload.message || payload.msg || payload.error || payload.reason || fallback;
}

function getFriendlyHttpMessage(status, fallback = '请求失败，请稍后重试') {
    const code = Number(status);
    if (!code) return fallback;
    if (code === 400) return fallback + '，提交的内容有误，请检查后再试。';
    if (code === 401) return fallback + '，登录状态已过期，请重新登录。';
    if (code === 403) return fallback + '，当前账号没有权限执行此操作。';
    if (code === 404) return fallback + '，相关资源不存在或已被删除。';
    if (code === 408) return fallback + '，请求等待时间过长，请稍后重试。';
    if (code === 409) return fallback + '，当前数据状态已变化，请刷新后再试。';
    if (code === 413) return fallback + '，提交的内容过大，请减少内容后再试。';
    if (code === 429) return fallback + '，操作过于频繁，请稍后再试。';
    if (code >= 500) return fallback + '，服务器处理时出现异常，请稍后重试。';
    return fallback + '，请求没有成功完成，请稍后重试。';
}

function isSuccessCode(code) {
    if (code === undefined || code === null || code === '') return true;
    const value = String(code).trim().toLowerCase();
    return value === '0' || value === '200' || value === 'success' || value === 'ok';
}

function isFailureSuccessValue(success) {
    if (success === true || success === 1) return false;
    if (success === false || success === 0) return true;
    const value = String(success).trim().toLowerCase();
    return value !== 'true' && value !== '1' && value !== 'success' && value !== 'ok';
}

function isFailureStatus(status) {
    if (status === undefined || status === null || status === '') return false;
    const value = String(status).trim().toLowerCase();
    if (/^\d+$/.test(value)) {
        return value !== '0' && value !== '200';
    }
    return [
        'error',
        'fail',
        'failed',
        'failure',
        'false',
        'invalid',
        'unauthorized',
        'forbidden',
        'timeout'
    ].includes(value);
}

function getPayloadProblem(payload) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        return null;
    }

    if (Object.prototype.hasOwnProperty.call(payload, 'success') && isFailureSuccessValue(payload.success)) {
        return {
            reason: pickMessage(payload, '操作没有成功完成，请稍后重试。'),
            meta: ''
        };
    }

    if (Object.prototype.hasOwnProperty.call(payload, 'code') && !isSuccessCode(payload.code)) {
        return {
            reason: pickMessage(payload, '操作没有成功完成，请稍后重试。'),
            meta: ''
        };
    }

    if (Object.prototype.hasOwnProperty.call(payload, 'status') && isFailureStatus(payload.status)) {
        return {
            reason: pickMessage(payload, '操作没有成功完成，请稍后重试。'),
            meta: ''
        };
    }

    return null;
}

async function parseFetchResponse(response) {
    const text = await response.text();
    if (!text) {
        return { json: null, text: '' };
    }

    try {
        return { json: JSON.parse(text), text };
    } catch (e) {
        return { json: null, text };
    }
}

async function assertApiResponse(response, fallbackMessage = '请求失败，请稍后重试') {
    const parsed = await parseFetchResponse(response);
    const payloadProblem = getPayloadProblem(parsed.json);

    if (parsed.text && !parsed.json) {
        throw createApiError({
            title: '服务响应异常',
            message: '服务器返回内容异常，请稍后重试。',
            detail: '',
            response
        });
    }

    if (!response.ok || payloadProblem) {
        throw createApiError({
            title: response.ok ? '请求失败' : '服务异常',
            message: payloadProblem ? payloadProblem.reason : pickMessage(parsed.json, getFriendlyHttpMessage(response.status, fallbackMessage)),
            detail: payloadProblem ? payloadProblem.meta : '',
            response,
            payload: parsed.json
        });
    }

    return parsed.json;
}

function normalizeApiError(error, fallbackTitle = '请求失败') {
    if (error && error.__apiError) {
        return error;
    }

    const rawMessage = typeof error === 'string' ? error : (error && error.message);
    let parsedPayload = null;
    if (typeof rawMessage === 'string') {
        const trimmed = rawMessage.trim();
        if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
            try {
                parsedPayload = JSON.parse(trimmed);
            } catch (e) {
                parsedPayload = null;
            }
        }
    }

    const payloadProblem = getPayloadProblem(parsedPayload);
    const message = (payloadProblem && payloadProblem.reason) ||
        pickMessage(parsedPayload, rawMessage || '网络异常或服务器无响应，请稍后重试');
    let title = fallbackTitle || '请求失败';
    let detail = payloadProblem ? payloadProblem.meta : '';

    if (message === 'Request Timeout' || (error && error.name === 'AbortError')) {
        title = '请求超时';
        detail = message;
        return {
            __apiError: true,
            title,
            message: '服务器响应时间过长，请稍后重试。',
            detail
        };
    } else if (!navigator.onLine) {
        title = '网络已断开';
        detail = message;
        return {
            __apiError: true,
            title,
            message: '当前设备看起来已经离线，请检查网络连接。',
            detail
        };
    } else if (error instanceof TypeError) {
        title = '网络错误';
        detail = message;
        return {
            __apiError: true,
            title,
            message: '无法连接到服务器，请检查网络、代理或服务是否正常运行。',
            detail
        };
    }

    return {
        __apiError: true,
        title,
        message,
        detail
    };
}

async function showApiError(error, title = '请求失败') {
    if (typeof Swal === 'undefined') return;

    const normalized = normalizeApiError(error, title);
    const lines = [normalized.message, normalized.detail].filter(Boolean);

    await Swal.fire({
        icon: 'error',
        title: normalized.title || title,
        html: '<div style="text-align:left;white-space:pre-wrap;line-height:1.6;">' +
            escapeHtml(lines.join('\n')) +
            '</div>',
        confirmButtonColor: '#2196f3',
        timer: 3000,
        timerProgressBar: true,
        showConfirmButton: false
    });
}

function createApiError({ title = '请求失败', message, detail, response, payload }) {
    const parts = [];
    const responseMessage = response ? getFriendlyHttpMessage(response.status, title) : '';
    if (responseMessage && responseMessage !== message) {
        parts.push(responseMessage);
    }
    if (detail) {
        parts.push(detail);
    }

    const error = new Error(message || pickMessage(payload));
    error.__apiError = true;
    error.title = title;
    error.message = message || pickMessage(payload);
    error.detail = parts.filter(Boolean).join('\n');
    error.response = response;
    error.payload = payload;
    return error;
}

/**
 * 通用请求方法
 * @param options {
 *   url: 请求地址（必填）
 *   method: GET / POST / PUT / DELETE，默认 POST
 *   data: JSON 请求数据或 GET 参数（非表单模式）
 *   formId: 表单ID（存在时走 FormData 提交）
 *   headers: 额外请求头
 *   loading: 是否显示 Loading（默认 false）
 *   loadingText: Loading 文案
 *   timeout: 超时时间，默认 10000ms
 *   showSuccess: 是否自动弹成功提示（默认 false）
 *   showError: 是否自动弹错误提示（默认 true）
 *   successMessage: 成功提示文案（可选，不传则用后端 message）
 *   errorMessage: 错误提示文案（可选，不传则用后端 message）
 *   redirect: 成功后跳转地址（可选）
 * }
 */
async function request(options) {
    const {
        url,
        method = "POST",
        data = null,
        formId = null,
        headers = {},
        loading = false,
        loadingText = "正在处理中...",
        timeout = REQUEST_TIMEOUT,
        showSuccess = false,
        showError = true,
        successMessage,
        errorMessage,
        redirect
    } = options;

    if (!url) {
        console.error("❌ request 需要 url 参数");
        return null;
    }

    // 是否显示 Loading
    if (loading) {
        showLoading(loadingText);
    }

    const csrfToken = getCsrfToken();

    try {
        let response;
        let fetchOptions = {};
        let finalUrl = url;

        // ==============================
        //  1：表单模式（支持文件上传）
        // ==============================

        if (formId) {

            if (loading) showLoading(loadingText);

            const form = document.getElementById(formId);
            if (!form) throw new Error(`未找到表单：${formId}`);

            const formData = new FormData(form);

            const csrfToken = getCsrfToken();
            const csrfHeader = getCsrfHeader();

            return new Promise(resolve => {

                const xhr = new XMLHttpRequest();
                xhr.open(method.toUpperCase(), url, true);

                // 设置 CSRF Token
                if (csrfToken) xhr.setRequestHeader(csrfHeader, csrfToken);

                xhr.onload = function () {

                    // 请求完成 → 隐藏 loading
                    if (loading) hideLoading();

                    let json = null;

                    try {
                        json = xhr.responseText ? JSON.parse(xhr.responseText) : null;
                    } catch (e) {
                        if (showError) {
                            showApiError(createApiError({
                                title: '服务响应异常',
                                message: '服务器返回内容异常，请稍后重试。',
                                detail: ''
                            }));
                        }
                        resolve(null);
                        return;
                    }

                    const payloadProblem = getPayloadProblem(json);
                    const ok = xhr.status >= 200 && xhr.status < 300 && !payloadProblem;

                    if (ok) {

                        if (redirect) {
                            // 有 redirect → 不弹 alert → 直接跳转
                            window.location.href = redirect;
                        } else {
                            if (showSuccess) {
                                Swal.fire("成功", pickMessage(json, "操作成功"), "success");
                            }
                        }

                        resolve(json);
                        return;
                    }

                    // ======= 失败处理 =======
                    if (showError) {
                        showApiError(createApiError({
                            title: '请求失败',
                            message: payloadProblem ? payloadProblem.reason : pickMessage(json, '操作失败，请稍后重试'),
                            detail: payloadProblem ? payloadProblem.meta : '',
                            response: { status: xhr.status, statusText: xhr.statusText },
                            payload: json
                        }));
                    }

                    resolve(json);
                };

                xhr.onerror = function () {
                    if (loading) hideLoading();
                    if (showError) {
                        showApiError(new TypeError("无法连接到服务器，请检查网络连接后再试"));
                    }
                    resolve(null);
                };

                xhr.send(formData);
            });
        }
        else {
            // ==============================
            //  2：普通 JSON / GET 请求
            // ==============================
            const defaultHeaders = {
                "Content-Type": "application/json;charset=UTF-8"
            };
            if (csrfToken) {
                defaultHeaders["X-CSRF-TOKEN"] = csrfToken;
            }

            const realHeaders = { ...defaultHeaders, ...headers };
            const upperMethod = method.toUpperCase();

            fetchOptions = {
                method: upperMethod,
                headers: realHeaders
            };

            if (upperMethod === "GET") {
                if (data) {
                    const params = new URLSearchParams(data).toString();
                    finalUrl += (finalUrl.includes("?") ? "&" : "?") + params;
                }
            } else {
                fetchOptions.body = JSON.stringify(data || {});
            }

            response = await timeoutPromise(timeout, fetch(finalUrl, fetchOptions));
            if (loading) hideLoading();
        }

        let json = null;

        try {
            json = await assertApiResponse(response, errorMessage || "请求失败，请稍后重试");
        } catch (apiError) {
            if (showError && typeof Swal !== "undefined") {
                await showApiError(apiError);
            }
            return apiError.payload || null;
        }

        // 成功逻辑
        const finalSuccessMsg = (json && json.message) || successMessage;

        if (showSuccess && finalSuccessMsg && typeof Swal !== "undefined") {
            await Swal.fire({
                icon: "success",
                title: "操作成功",
                text: finalSuccessMsg,
                confirmButtonText: "确定"
            });
        }

        if (redirect) {
            window.location.href = redirect;
        }

        return json;

    } catch (err) {
        console.error(" 请求异常：", err);
        if (loading) hideLoading();

        if (showError && typeof Swal !== "undefined") {
            await showApiError(errorMessage ? new Error(errorMessage) : err, '网络错误');
        }

        throw err;

    }
}

/**
 * 绑定表单提交（带必填校验 + 自动滚动 + 自动调用 request）
 *
 * @param formId   表单ID
 * @param config {
 *   url: 提交地址（必填）
 *   method: 请求方式，默认 POST
 *   required: 基础必填字段数组（按 input 的 id）
 *   extraRequiredByCloudType: { 1: [...], 2: [...] } 按 currentCloudType 动态必填
 *   scrollToError: 是否自动滚动到第一个错误字段，默认 true
 *   loading: 是否显示 loading，默认 true
 *   loadingText: loading 文案
 *   redirect: 成功后跳转地址
 *   showSuccess: 是否自动弹成功提示，默认 true
 *   showError: 是否自动弹错误提示，默认 true
 *   onSuccess: function(res) 自定义成功回调（可选）
 *   onError: function(res) 自定义失败回调（可选）
 * }
 */
function bindFormSubmit(formId, config) {
    const form = document.getElementById(formId);
    if (!form) {
        console.error(`未找到表单：${formId}`);
        return;
    }

    form.addEventListener("submit", async function (e) {
        e.preventDefault();

        const {
            url,
            method = "POST",
            required = [],
            extraRequiredByCloudType = {},
            scrollToError = true,
            loading = true,
            loadingText = "正在提交，请稍候...",
            redirect,
            showSuccess = true,
            showError = true,
            onSuccess,
            onError
        } = config;

        if (!url) {
            console.error("bindFormSubmit 需要 config.url");
            return;
        }

        // 1. 组装必填字段
        let requiredFields = [...required];
        if (extraRequiredByCloudType && typeof currentCloudType !== "undefined") {
            const extra = extraRequiredByCloudType[currentCloudType];
            if (extra && extra.length) {
                requiredFields = requiredFields.concat(extra);
            }
        }

        // 2. 校验必填字段
        let isValid = true;
        const invalidElements = [];

        requiredFields.forEach(fieldId => {
            const el = document.getElementById(fieldId);
            if (!el || !el.value || !el.value.trim()) {
                isValid = false;
                if (el) {
                    el.classList.add("error");
                    invalidElements.push(el);
                }
            } else {
                el.classList.remove("error");
            }
        });

        if (!isValid) {
            if (invalidElements.length > 0 && scrollToError) {
                invalidElements[0].scrollIntoView({ behavior: "smooth", block: "center" });
                invalidElements[0].focus();
            }

            if (typeof Swal !== "undefined") {
                Swal.fire({
                    icon: "error",
                    title: "验证失败",
                    text: "请填写所有必填字段",
                    confirmButtonText: "确定"
                });
            }
            return;
        }

        // 3. 调用统一 request（表单模式）
        try {
            const res = await request({
                url: url,
                method: method,
                formId: formId,
                loading: loading,
                loadingText: loadingText,
                redirect: redirect,
                showSuccess: showSuccess,
                showError: showError
            });

            if (res && res.success) {
                if (typeof onSuccess === "function") {
                    onSuccess(res);
                }
            } else {
                if (typeof onError === "function") {
                    onError(res);
                }
            }
        } catch (err) {
            if (typeof onError === "function") {
                onError(null, err);
            }
        }
    });
}

function httpGet(url, params = {}, options = {}) {
    return request({
        url: url,
        method: "GET",
        data: params,
        ...options
    });
}

function httpPost(url, data = {}, options = {}) {
    return request({
        url: url,
        method: "POST",
        data: data,
        ...options
    });
}

function httpPut(url, data = {}, options = {}) {
    return request({
        url: url,
        method: "PUT",
        data: data,
        ...options
    });
}

function httpDelete(url, data = {}, options = {}) {
    return request({
        url: url,
        method: "DELETE",
        data: data,
        ...options
    });
}

    window.request = request;
    window.bindFormSubmit = bindFormSubmit;
    window.httpGet = httpGet;
    window.httpPost = httpPost;
    window.httpPut = httpPut;
    window.httpDelete = httpDelete;
    window.OciRequestUtils = {
        getPayloadProblem,
        normalizeApiError,
        showApiError,
        assertApiResponse
    };
})();
