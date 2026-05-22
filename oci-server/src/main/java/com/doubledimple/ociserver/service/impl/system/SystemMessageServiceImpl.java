package com.doubledimple.ociserver.service.impl.system;

import cn.hutool.core.bean.BeanUtil;
import cn.hutool.core.util.IdUtil;
import com.doubledimple.dao.entity.Message;
import com.doubledimple.dao.repository.MessageRepository;
import com.doubledimple.ociserver.pojo.request.SystemMessageRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.SystemMessageService;
import com.doubledimple.ociserver.utils.PageUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import javax.persistence.criteria.Predicate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName SystemMessageServiceImpl
 * @Description TODO
 * @Author renyx
 * @Date 2025-12-13 05:42
 */
@Service
@Slf4j
public class SystemMessageServiceImpl implements SystemMessageService {

    @Resource
    private MessageRepository messageRepository;


    @Override
    public Page<Message> getSystemMessagePage(SystemMessageRequest request) {
        Specification<Message> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };
        return PageUtils.findWithSpec(messageRepository, request, spec);
    }

    @Override
    @Transactional
    public ApiResponse updateAllRead() {
        messageRepository.markAllAsRead();
        return ApiResponse.success();
    }

    @Override
    @Transactional
    public ApiResponse getMessage(SystemMessageRequest messageRequest) {
        Message message = messageRepository.findMessageByBusinessId(messageRequest.getBusinessId());
        if (message != null){
            message.setReadStatus(1);
            messageRepository.save(message);
        }
        return ApiResponse.success(message);
    }

    @Override
    @Transactional
    public ApiResponse saveMessage(SystemMessageRequest messageRequest) {
        try {
            Message message = new Message();
            LocalDateTime now = LocalDateTime.now();
            BeanUtil.copyProperties(messageRequest, message);
            message.setBusinessId(IdUtil.getSnowflakeNextIdStr());
            message.setReadStatus(0);
            message.setCreateTime(now);
            message.setUpdateTime(now);
            messageRepository.save(message);
            return ApiResponse.success();
        } catch (Exception e) {
            log.warn("保存消息失败:{}", e.getMessage());
            return ApiResponse.error("保存消息失败");
        }
    }

    @Override
    public ApiResponse countUnreadMessage() {
        Long aLong = messageRepository.countByReadStatus(0);
        if (aLong == null) aLong = 0L;
        return ApiResponse.success(aLong);
    }

    @Override
    @Transactional
    public ApiResponse deleteMessage(SystemMessageRequest messageRequest) {
        Message message = messageRepository.findMessageByBusinessId(messageRequest.getBusinessId());
        if (message != null){
            messageRepository.delete(message);
        }
        return ApiResponse.success();
    }
}
