<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 实例列表</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/styles.css">
    <link rel="stylesheet" href="/css/app/machine_list.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<#--<#include "common/version_info.ftl">-->

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->



    <!-- Main Content -->
    <main class="main-content">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-microchip"></i>
                <span>实例列表</span>
            </h1>
            <div class="btn-group">
                <a href="/tenants/add" class="btn btn-success">
                    <i class="fas fa-plus"></i>
                    <span>添加API</span>
                </a>
                <a href="/tenants/list" class="btn btn-primary">
                    <i class="fas fa-arrow-left"></i>
                    <span>返回首页</span>
                </a>
            </div>
        </div>

        <div class="table-card">
            <div class="table-responsive">
                <table class="table">
                    <thead>
                    <tr>
                        <th>ID</th>
                        <th>OCPU</th>
                        <th>内存(GB)</th>
                        <th>磁盘(GB)</th>
                        <th>循环时间(秒)</th>
                        <th>实例数量</th>
                        <th>系统架构</th>
                        <th>Root密码</th>
                        <th>状态</th>
                        <th>公网IP</th>
                        <th>创建时间</th>
                        <th>操作</th>
                    </tr>
                    </thead>
                    <tbody>
                    <#if bootInstances?has_content>
                    <#list bootInstances as bootInstance>
                        <tr>
                            <td><span class="truncate" data-fulltext="${bootInstance.id}">${bootInstance.id}</span></td>
                            <td>${bootInstance.ocpu}</td>
                            <td>${bootInstance.memory}</td>
                            <td>${bootInstance.disk}</td>
                            <td>${bootInstance.loopTime}</td>
                            <td>${bootInstance.instanceCount}</td>
                            <td>${bootInstance.architecture}</td>
                            <td>
                                <span class="password-field" data-password="${bootInstance.rootPassword}">********</span>
                            </td>
                            <td>
                                        <span class="status-badge
                                            <#if bootInstance.status == 0>status-offline
                                            <#elseif bootInstance.status == 1>status-starting
                                            <#else>status-running
                                            </#if>">
                                            <#if bootInstance.status == 0>未开机
                                            <#elseif bootInstance.status == 1>开机中
                                            <#else>已开机
                                            </#if>
                                        </span>
                            </td>
                            <td><span class="truncate" data-fulltext="${bootInstance.publicIp}">${bootInstance.publicIp}</span></td>
                            <td>${bootInstance.createdAt}</td>
                            <td>
                                <div class="btn-group">
                                    <form action="/boot/startBoot" method="get">
                                        <input type="hidden" name="bootId" value="${bootInstance.id}">
                                        <button type="submit" class="btn btn-primary"
                                                <#if bootInstance.status != 0>disabled</#if>>
                                            <i class="fas fa-play"></i>
                                        </button>
                                    </form>
                                    <form action="/boot/stopBoot" method="get">
                                        <input type="hidden" name="bootId" value="${bootInstance.id}">
                                        <button type="submit" class="btn btn-warning"
                                                <#if bootInstance.status != 1>disabled</#if>>
                                            <i class="fas fa-stop"></i>
                                        </button>
                                    </form>
                                    <form action="/boot/deleteBoot" method="get">
                                        <input type="hidden" name="bootId" value="${bootInstance.id}">
                                        <button type="submit" class="btn btn-danger">
                                            <i class="fas fa-trash"></i>
                                        </button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                    </#list>
                    <#else>
                        <!-- 列表为空时的处理 -->
                    </#if>
                    </tbody>
                </table>
            </div>
        </div>
    </main>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/machine_list.js"></script>
</body>
</html>