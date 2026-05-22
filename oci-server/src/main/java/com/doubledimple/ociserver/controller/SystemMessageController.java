package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Message;
import com.doubledimple.ociserver.pojo.request.SystemMessageRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.SystemMessageService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;

/**
 * @version 1.0.0
 * @ClassName SystemMessageController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-13 05:52
 */
@Controller
@RequestMapping("/sysMessage")
@Slf4j
public class SystemMessageController extends BaseController{


    @Resource
    private SystemMessageService systemMessageService;


    /**
     * 系统消息列表(支持分页)
     */
    @PostMapping("/list")
    @ResponseBody
    public ApiResponse listMessage(@RequestBody SystemMessageRequest messageRequest) {
        try {
            Page<Message> page = systemMessageService.getSystemMessagePage(messageRequest);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.error("查询消息列表是失败", e);
            return ApiResponse.error("查询消息列表失败: " + e.getMessage());
        }
    }


    //将消息全部设置为已读
    @PostMapping("/read")
    @ResponseBody
    public ApiResponse readAllMessage() {
        try {
            return systemMessageService.updateAllRead();
        } catch (Exception e) {
            log.error("将消息全部设置为已读失败", e);
            return ApiResponse.error("将消息全部设置为已读失败: " + e.getMessage());
        }
    }


    //查询消息详情
    @PostMapping("/get")
    @ResponseBody
    public ApiResponse getMessage(@RequestBody SystemMessageRequest messageRequest) {
        try {
            return systemMessageService.getMessage(messageRequest);
        } catch (Exception e) {
            log.error("查询消息详情失败", e);
            return ApiResponse.error("查询消息详情失败: " + e.getMessage());
        }
    }

    //查询未读消息数量
    @PostMapping("/countUnread")
    @ResponseBody
    public ApiResponse countUnreadMessage() {
        try {
            return systemMessageService.countUnreadMessage();
        } catch (Exception e) {
            log.error("查询未读消息数量失败", e);
            return ApiResponse.error("查询未读消息数量失败: " + e.getMessage());
        }
    }

    //删除消息
    @PostMapping("/del")
    @ResponseBody
    public ApiResponse deleteMessage(@RequestBody SystemMessageRequest messageRequest) {
        try {
            return systemMessageService.deleteMessage(messageRequest);
        } catch (Exception e) {
            log.error("删除消息失败", e);
            return ApiResponse.error("删除消息失败: " + e.getMessage());
        }
    }
}
