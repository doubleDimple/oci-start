(() => {
let loadingStartTime = 0;

function t(key, fallback, params) {
    const dict = window.I18N || window.i18n || {};
    let value = dict[key] || fallback || key;
    if (params && typeof value === 'string') {
        Object.keys(params).forEach(name => {
            value = value.replace(new RegExp('\\{' + name + '\\}', 'g'), params[name]);
        });
    }
    return value;
}

function showLoading(text = t('common_loading', 'Loading...')) {
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

function pickMessage(payload, fallback = t('request_default_fail', 'The request failed. Please try again later.')) {
    if (!payload) return fallback;
    if (typeof payload === 'string') return payload || fallback;
    return payload.message || payload.msg || payload.error || payload.reason || fallback;
}

function getFriendlyHttpMessage(status, fallback = t('request_default_fail', 'The request failed. Please try again later.')) {
    const code = Number(status);
    if (!code) return fallback;
    if (code === 400) return fallback + t('request_http_400_suffix', ', please check the submitted content and try again.');
    if (code === 401) return fallback + t('request_http_401_suffix', ', your login has expired. Please sign in again.');
    if (code === 403) return fallback + t('request_http_403_suffix', ', this account does not have permission to perform this action.');
    if (code === 404) return fallback + t('request_http_404_suffix', ', the resource does not exist or has been deleted.');
    if (code === 408) return fallback + t('request_http_408_suffix', ', the request took too long. Please try again later.');
    if (code === 409) return fallback + t('request_http_409_suffix', ', the data has changed. Please refresh and try again.');
    if (code === 413) return fallback + t('request_http_413_suffix', ', the submitted content is too large. Please reduce it and try again.');
    if (code === 429) return fallback + t('request_http_429_suffix', ', too many operations. Please try again later.');
    if (code >= 500) return fallback + t('request_http_5xx_suffix', ', the server could not process this request. Please try again later.');
    return fallback + t('request_http_generic_suffix', ', the request was not completed successfully. Please try again later.');
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
            reason: pickMessage(payload, t('request_action_fail', 'The operation was not completed. Please try again later.')),
            meta: ''
        };
    }

    if (Object.prototype.hasOwnProperty.call(payload, 'code') && !isSuccessCode(payload.code)) {
        return {
            reason: pickMessage(payload, t('request_action_fail', 'The operation was not completed. Please try again later.')),
            meta: ''
        };
    }

    if (Object.prototype.hasOwnProperty.call(payload, 'status') && isFailureStatus(payload.status)) {
        return {
            reason: pickMessage(payload, t('request_action_fail', 'The operation was not completed. Please try again later.')),
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

async function assertApiResponse(response, fallbackMessage = t('request_default_fail', 'The request failed. Please try again later.')) {
    const parsed = await parseFetchResponse(response);
    const payloadProblem = getPayloadProblem(parsed.json);

    if (parsed.text && !parsed.json) {
        throw createApiError({
            title: t('request_invalid_response_title', 'Unexpected response'),
            message: t('request_invalid_response_message', 'The server returned an unexpected response. Please try again later.'),
            detail: '',
            response
        });
    }

    if (!response.ok || payloadProblem) {
        throw createApiError({
            title: response.ok ? t('request_fail_title', 'Request failed') : t('request_service_error_title', 'Service unavailable'),
            message: payloadProblem ? payloadProblem.reason : pickMessage(parsed.json, getFriendlyHttpMessage(response.status, fallbackMessage)),
            detail: payloadProblem ? payloadProblem.meta : '',
            response,
            payload: parsed.json
        });
    }

    return parsed.json;
}

function normalizeApiError(error, fallbackTitle = t('request_fail_title', 'Request failed')) {
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
        pickMessage(parsedPayload, rawMessage || t('request_network_or_server_error', 'Network error or no server response. Please try again later.'));
    let title = fallbackTitle || t('request_fail_title', 'Request failed');
    let detail = payloadProblem ? payloadProblem.meta : '';

    if (message === 'Request Timeout' || (error && error.name === 'AbortError')) {
        title = t('request_timeout_title', 'Request timed out');
        detail = message;
        return {
            __apiError: true,
            title,
            message: t('request_timeout_message', 'The server took too long to respond. Please try again later.'),
            detail
        };
    } else if (!navigator.onLine) {
        title = t('request_offline_title', 'Network disconnected');
        detail = message;
        return {
            __apiError: true,
            title,
            message: t('request_offline_message', 'This device appears to be offline. Please check your network connection.'),
            detail
        };
    } else if (error instanceof TypeError) {
        title = t('request_network_title', 'Network error');
        detail = message;
        return {
            __apiError: true,
            title,
            message: t('request_network_message', 'Unable to connect to the server. Please check your network, proxy, or service status.'),
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

async function showApiError(error, title = t('request_fail_title', 'Request failed')) {
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

function createApiError({ title = t('request_fail_title', 'Request failed'), message, detail, response, payload }) {
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
        loadingText = t('common_processing', 'Processing...'),
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
            if (!form) {
                throw new Error(t('request_form_missing_with_id', 'Form not found: {formId}', { formId }));
            }

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
                                title: t('request_invalid_response_title', 'Unexpected response'),
                                message: t('request_invalid_response_message', 'The server returned an unexpected response. Please try again later.'),
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
                                Swal.fire(t('request_success_title', 'Success'), pickMessage(json, t('request_success_message', 'Operation completed successfully.')), "success");
                            }
                        }

                        resolve(json);
                        return;
                    }

                    // ======= 失败处理 =======
                    if (showError) {
                        showApiError(createApiError({
                            title: t('request_fail_title', 'Request failed'),
                            message: payloadProblem ? payloadProblem.reason : pickMessage(json, t('request_operation_fail', 'Operation failed. Please try again later.')),
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
                        showApiError(new TypeError(t('request_network_message_short', 'Unable to connect to the server. Please check your network and try again.')));
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
            json = await assertApiResponse(response, errorMessage || t('request_default_fail', 'The request failed. Please try again later.'));
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
                title: t('request_success_title', 'Success'),
                text: finalSuccessMsg,
                confirmButtonText: t('common_confirm', 'OK')
            });
        }

        if (redirect) {
            window.location.href = redirect;
        }

        return json;

    } catch (err) {
        console.error("Request exception:", err);
        if (loading) hideLoading();

        if (showError && typeof Swal !== "undefined") {
            await showApiError(errorMessage ? new Error(errorMessage) : err, t('request_network_title', 'Network error'));
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
            loadingText = t('common_submitting', 'Submitting, please wait...'),
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
                title: t('request_validation_fail_title', 'Validation failed'),
                text: t('request_required_fields', 'Please fill in all required fields.'),
                    confirmButtonText: t('common_confirm', 'OK')
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
        assertApiResponse,
        getFriendlyHttpMessage,
        pickMessage,
        t
    };
})();
