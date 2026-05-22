package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.dao.entity.TelegramUser;
import com.doubledimple.dao.repository.TelegramUserRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.telegram.telegrambots.meta.generics.BotSession;
import org.telegram.telegrambots.updatesreceivers.DefaultBotSession;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Service
@Slf4j
public class TelegramUserService {

    @Resource
    private TelegramUserRepository telegramUserRepository;

    @Resource
    private TelegramBotConfig telegramBotConfig;

    /**
     * 检查用户是否有权限
     */
    public boolean isUserAuthorized(Long userId) {
        return telegramUserRepository.existsByUserIdAndIsAuthorized(userId, true);
    }

    public TelegramUser getUserById(Long userId) {
        return telegramUserRepository.findByUserId(userId).orElse(null);
    }

    public TelegramUser getUserById() {
        List<TelegramUser> all = telegramUserRepository.findAll();
        if (!CollectionUtils.isEmpty( all)){
            return all.get(0);
        }else {
            return null;
        }
    }

    /**
     * 注册新用户
     */
    @Transactional
    public TelegramUser registerUser(TelegramUser telegramUser) {
        final Long userId = telegramUser.getUserId();
        final String username = telegramUser.getUsername();
        final String firstName = telegramUser.getFirstName();
        final String lastName = telegramUser.getLastName();
        Optional<TelegramUser> existingUser = telegramUserRepository.findByUserId(userId);

        if (existingUser.isPresent()) {
            // 更新最后活跃时间
            TelegramUser user = existingUser.get();
            user.setLastActiveAt(LocalDateTime.now());
            user.setActive(telegramUser.getActive());
            return telegramUserRepository.save(user);
        } else {
            // 创建新用户
            TelegramUser newUser = new TelegramUser();
            newUser.setUserId(userId);
            newUser.setUsername(username);
            newUser.setFirstName(firstName);
            newUser.setLastName(lastName);
            newUser.setIsAuthorized(true);
            newUser.setActive(telegramUser.getActive());

            TelegramUser savedUser = telegramUserRepository.save(newUser);
            log.info("新用户注册成功: userId={}, username={}", userId, username);
            return savedUser;
        }
    }

    /**
     * 更新用户最后活跃时间
     */
    @Transactional
    public void updateUserLastActive(Long userId) {
        Optional<TelegramUser> user = telegramUserRepository.findByUserId(userId);
        if (user.isPresent()) {
            user.get().setLastActiveAt(LocalDateTime.now());
            telegramUserRepository.save(user.get());
        }
    }

    //返回false表示无权限
    public boolean checkUser(Long id) {
        TelegramUser firstUser = getUserById();
        if (firstUser != null){
            return firstUser.getUserId().equals(id);
        }else {
            return true;
        }
    }

    @Transactional
    public void delCurrentBot() {
        telegramUserRepository.deleteAll();
        telegramBotConfig.stopBot();
    }


    public DefaultBotSession getSession(){
        DefaultBotSession botSession = telegramBotConfig.getBotSession();
        return botSession;
    }
}
