<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 快速添加API</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">

    <link rel="stylesheet" href="/css/app/tenant_speed_add.css">
    <link rel="stylesheet" href="/css/common/loading.css">


    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->
<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">${msg.get("speedadd.config")}</h1>
        </div>

        <div class="form-card">
            <!-- 当前选择的云厂商显示 -->
            <div class="cloud-provider-indicator" id="cloudProviderIndicator">
                <img id="currentProviderLogo" src="/images/oracle.png" alt="Oracle Cloud">
                <span>${msg.get("tenant.provider")}: <strong id="currentProviderName">Oracle Cloud</strong></span>
            </div>

            <h2 class="form-title">${msg.get("tenant.apiDes")}</h2>
            <div id="errorAlert" class="alert alert-error">
                <i class="fas fa-exclamation-circle"></i>
                <span id="errorMessage"></span>
            </div>
            <div id="successAlert" class="alert alert-success">
                <i class="fas fa-check-circle"></i>
                <span id="successMessage"></span>
            </div>

            <!-- 配置文本导入区域 -->
            <div class="form-group">
                <label class="form-label">${msg.get("speedadd.config")}</label>
                <div class="config-textarea-wrapper">
                    <textarea id="configInput" class="config-textarea"
                              placeholder="${msg.get("speedadd.configDes")}"></textarea>
                    <div class="drag-overlay">
                        <i class="fas fa-file-import"></i>
                        <span>${msg.get("speedadd.copyFile")}</span>
                    </div>
                </div>
            </div>

            <form action="/tenants/save" method="post" enctype="multipart/form-data" id="apiForm">
                <input type="hidden" id="status" name="status" value="0"/>
                <input type="hidden" id="cloudType" name="cloudType" value="1"/>

                <div class="form-group">
                    <label class="form-label" for="userName">UserName</label>
                    <input type="text" class="form-control" id="userName" name="userName" required>
                </div>

                <!-- 复用字段，根据云厂商类型动态改变标签 -->
                <div class="form-group">
                    <label class="form-label" id="tenantIdLabel" for="tenantId">User(API user)</label>
                    <input type="text" class="form-control" id="tenantId" name="tenantId" required>
                </div>

                <div class="form-group">
                    <label class="form-label" id="fingerprintLabel" for="fingerprint">Fingerprint(API fingerprint)</label>
                    <input type="text" class="form-control" id="fingerprint" name="fingerprint" required>
                </div>

                <div class="form-group">
                    <label class="form-label" id="tenancyLabel" for="tenancy">Tenancy(API tenancy)</label>
                    <input type="text" class="form-control" id="tenancy" name="tenancy" required>
                </div>

                <div class="form-group" id="regionGroup">
                    <label class="form-label" id="regionLabel" for="region">Region</label>
                    <select class="form-control" id="region" name="region" required>
                        <option value="" disabled selected>${msg.get("openBoot.selectRegion")}</option>
                        <!-- Oracle Cloud 区域选项 -->
                        <optgroup id="oracleRegions" label="Oracle Cloud 区域">
                            <option value="af-johannesburg-1">中东非洲-南非中部约翰内斯堡</option>
                            <option value="af-casablanca-1">中东非洲-摩洛哥卡萨布兰卡</option>
                            <option value="ap-chuncheon-1">亚太-韩国北部春川</option>
                            <option value="ap-hyderabad-1">亚太-印度南部海得拉巴</option>
                            <option value="ap-melbourne-1">亚太-澳大利亚东南部墨尔本</option>
                            <option value="ap-mumbai-1">亚太-印度西部孟买</option>
                            <option value="ap-osaka-1">亚太-日本中部大阪</option>
                            <option value="ap-seoul-1">亚太-韩国中部首尔</option>
                            <option value="ap-kulai-2">亚太-马来西亚古来</option>
                            <option value="ap-singapore-1">亚太-新加坡</option>
                            <option value="ap-singapore-2">亚太-新加坡西</option>
                            <option value="ap-sydney-1">亚太-澳大利亚东部悉尼</option>
                            <option value="ap-tokyo-1">亚太-日本东部东京</option>
                            <option value="ap-batam-1">亚太-印度尼西亚巴淡</option>
                            <option value="ca-montreal-1">北美-加拿大东南部蒙特利尔</option>
                            <option value="ca-toronto-1">北美-加拿大东南部多伦多</option>
                            <option value="eu-amsterdam-1">欧洲-荷兰西北部阿姆斯特丹</option>
                            <option value="eu-frankfurt-1">欧洲-德国中部法兰克福</option>
                            <option value="eu-jovanovac-1">欧洲-塞尔维亚中部乔万诺瓦茨</option>
                            <option value="eu-madrid-1">欧洲-西班牙中部马德里-1</option>
                            <option value="eu-madrid-3">欧洲-西班牙中部马德里-3</option>
                            <option value="eu-marseille-1">欧洲-法国南部马赛</option>
                            <option value="eu-milan-1">欧洲-意大利西北部米兰</option>
                            <option value="eu-turin-1">欧洲-意大利西北部都灵</option>
                            <option value="eu-paris-1">欧洲-法国中部巴黎</option>
                            <option value="eu-stockholm-1">欧洲-瑞典中部斯德哥尔摩</option>
                            <option value="eu-zurich-1">欧洲-瑞士北部苏黎世</option>
                            <option value="il-jerusalem-1">欧洲-以色列中部耶路撒冷</option>
                            <option value="me-abudhabi-1">中东-阿联酋阿布扎比</option>
                            <option value="me-dubai-1">中东-阿联酋迪拜</option>
                            <option value="me-jeddah-1">中东-沙特阿拉伯西部吉达</option>
                            <option value="me-riyadh-1">中东-沙特阿拉伯首都利雅得</option>
                            <option value="mx-monterrey-1">北美-墨西哥东北部蒙特雷</option>
                            <option value="mx-queretaro-1">北美-墨西哥中部克雷塔罗</option>
                            <option value="sa-bogota-1">南美-哥伦比亚中部波哥大</option>
                            <option value="sa-santiago-1">南美-智利中部圣地亚哥</option>
                            <option value="sa-saopaulo-1">南美-巴西东部圣保罗</option>
                            <option value="sa-vinhedo-1">南美-巴西南部维涅杜</option>
                            <option value="uk-cardiff-1">欧洲-英国西部加的夫</option>
                            <option value="uk-london-1">欧洲-英国南部伦敦</option>
                            <option value="us-ashburn-1">北美-美国东部阿什本</option>
                            <option value="us-chicago-1">北美-美国中西部芝加哥</option>
                            <option value="us-phoenix-1">北美-美国西部凤凰城</option>
                            <option value="us-sanjose-1">北美-美国西部圣何塞</option>
                            <option value="sa-valparaiso-1">南美-智利西部瓦尔帕莱索</option>
                        </optgroup>
                    </select>
                </div>

                <div class="form-group">
                    <label class="form-label" for="keyFileStr">${msg.get("tenant.secretFile")}</label>
                    <div class="file-input-wrapper">
                        <label class="file-input-label">
                            <i class="fas fa-upload"></i>
                            <span>${msg.get("tenant.selectFile")}</span>
                        </label>
                        <input type="file" id="keyFileStr" name="keyFileStr" required>
                    </div>
                </div>

                <div class="form-actions">
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save"></i>
                        ${msg.get("common.save")}
                    </button>
                    <a href="/tenants/list" class="btn btn-secondary">
                        <i class="fas fa-times"></i>
                        ${msg.get("common.cancel")}
                    </a>
                </div>
            </form>
        </div>
        </div><!-- /.page-card -->
    </main>
</div>

<script>
    window.I18N = {
        tenant_selectFile: "${msg.get('tenant.selectFile')?js_string}",
        speedadd_json: "${msg.get('speedadd.json')?js_string}",
        speedadd_gcpJson: "${msg.get('speedadd.gcpJson')?js_string}",
        speedadd_errorJson: "${msg.get('speedadd.errorJson')?js_string}",
        speedadd_ociJsonSucc: "${msg.get('speedadd.ociJsonSucc')?js_string}",
        speedadd_ociJsonnoFund: "${msg.get('speedadd.ociJsonnoFund')?js_string}",
        speedadd_gcpJsonnoFund: "${msg.get('speedadd.gcpJsonnoFund')?js_string}",
        speedadd_gcpJsonnoSucc: "${msg.get('speedadd.gcpJsonnoSucc')?js_string}",
        speedadd_gcpJsonnoError: "${msg.get('speedadd.gcpJsonnoError')?js_string}",
        speedadd_waitCommit: "${msg.get('speedadd.waitCommit')?js_string}",
        openBoot_select: "${msg.get('openBoot.select')?js_string}",
        speedadd_ociJson: "${msg.get('speedadd.ociJson')?js_string}"


    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/tenant_speed_add.js"></script>
</body>
</html>