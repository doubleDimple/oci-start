package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.CloudSshFolder;
import com.doubledimple.ociserver.pojo.dto.FolderDTO;
import com.doubledimple.ociserver.pojo.request.CloudSshConnReq;
import com.doubledimple.ociserver.pojo.request.CreateFolderReq;
import com.doubledimple.ociserver.pojo.request.UpdateFolderReq;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.CloudSshFolderService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;


/**
 * @version 1.0.0
 * @ClassName SshController
 * @Description TODO
 * @Author ssh连接终端
 * @Date 2025-11-07 09:44
 */
@Controller
@RequestMapping("/ssh")
@Slf4j
public class SshController extends BaseController{

    @Resource
    private CloudSshFolderService cloudSshFolderService;


    @RequestMapping("/terminal")
    public String terminal(HttpServletRequest request, Model model){
        model.addAttribute("activePage", "ssh-terminal");
        return "ssh_terminal";
    }


    /** 文件夹树 */
    @GetMapping("/folders/tree")
    @ResponseBody
    public ApiResponse getFolderTree() {
        return cloudSshFolderService.getFolderTree();
    }

    /** 指定文件夹下实例 */
    @GetMapping("/folders/{id}/instances")
    @ResponseBody
    public ApiResponse getInstancesByFolder(@PathVariable Long id) {
        return ApiResponse.success(cloudSshFolderService.findByFolderId(id));
    }

    /** 新增文件夹 */
    @PostMapping("/folders")
    @ResponseBody
    public ApiResponse createFolder(@RequestBody CreateFolderReq req) {
        try {
            CloudSshFolder folder = cloudSshFolderService.createFolder(req.getName(), req.getParentId(), req.getSortOrder());
            return ApiResponse.success(FolderDTO.from(folder));
        } catch (IllegalArgumentException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("createFolder error", e);
            return ApiResponse.error("创建失败");
        }
    }

    /** 修改文件夹（重命名 / 移动 / 调整排序） */
    @PutMapping("/folders/{id}")
    @ResponseBody
    public ApiResponse updateFolder(@PathVariable Long id, @RequestBody UpdateFolderReq req) {
        try {
            CloudSshFolder folder = cloudSshFolderService.updateFolder(
                    id, req.getName(), req.getParentId(), req.getSortOrder());
            return ApiResponse.success(FolderDTO.from(folder));
        } catch (IllegalArgumentException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("updateFolder error", e);
            return ApiResponse.error("更新失败");
        }
    }

    /**
     * 删除文件夹
     * @param force true 表示强制删除：将子文件夹与实例“上移到父级”（或置为未分组）后再删；false：当存在子元素时报错
     */
    @DeleteMapping("/folders/{id}")
    @ResponseBody
    public ApiResponse deleteFolder(@PathVariable Long id,
                                    @RequestParam(value = "force", defaultValue = "false") boolean force) {
        try {
            cloudSshFolderService.deleteFolder(id, force);
            return ApiResponse.success(true);
        } catch (IllegalArgumentException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("deleteFolder error", e);
            return ApiResponse.error("删除失败");
        }
    }

    /**
     * 创建 SSH 实例并绑定文件夹
     */
    @PostMapping("/instances/create")
    @ResponseBody
    public ApiResponse createInstance(@RequestBody CloudSshConn conn) {
        try {
            CloudSshConn saved = cloudSshFolderService.createInstance(conn);
            return ApiResponse.success(saved);
        } catch (Exception e) {
            log.error("createInstance error", e);
            return ApiResponse.error("实例创建失败");
        }
    }

    /**
     * 获取实例详情
     */
    @GetMapping("/instances/{id}")
    @ResponseBody
    public ApiResponse getInstance(@PathVariable Long id) {
        try {
            CloudSshConn conn = cloudSshFolderService.findInstanceById(id);
            if (conn == null) {
                return ApiResponse.error("实例不存在");
            }
            return ApiResponse.success(conn);
        } catch (Exception e) {
            log.error("getInstance error", e);
            return ApiResponse.error("查询失败");
        }
    }

    /**
     * 创建实例（替代旧的 /instances/create）
     */
    @PostMapping("/instances")
    @ResponseBody
    public ApiResponse createInstanceNew(@RequestBody CloudSshConn conn) {
        try {
            CloudSshConn saved = cloudSshFolderService.createInstance(conn);
            return ApiResponse.success(saved);
        } catch (Exception e) {
            log.error("createInstance error", e);
            return ApiResponse.error("实例创建失败");
        }
    }

    /**
     * 更新实例信息
     */
    @PutMapping("/instances/{id}")
    @ResponseBody
    public ApiResponse updateInstance(@PathVariable Long id, @RequestBody CloudSshConnReq req) {
        try {
            CloudSshConn updated = cloudSshFolderService.updateInstance(id, req);
            return ApiResponse.success(updated);
        } catch (IllegalArgumentException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("updateInstance error", e);
            return ApiResponse.error("更新失败");
        }
    }


}
