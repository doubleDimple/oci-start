package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.config.annotations.AuditLog;
import com.doubledimple.ociserver.config.annotations.CheckIpBan;
import com.doubledimple.ociserver.config.annotations.CheckLoginUser;
import org.springframework.stereotype.Controller;

@Controller
@CheckIpBan
@CheckLoginUser
@AuditLog
public abstract class BaseController {
}
