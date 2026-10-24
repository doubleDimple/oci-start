package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

import javax.annotation.Resource;

/**
 * api的实例详情页面
 * @author doubleDimple
 * @date 2024:11:10日 00:46
 */
@Controller
@RequestMapping("/instanceDetail")
@Slf4j
public class OciInstanceDetailController  extends BaseController{

    @Resource
    OracleInstanceService oracleInstanceService;

}
