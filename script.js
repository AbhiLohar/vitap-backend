
    /*<![CDATA[*/

    var captchaType = 1;
    var otpSentAt = null;
    var securityOtpPending = null;

    $(document).ready(function() {
        $('input').keyup(function(event) {
            if (event.which === 13) {
                event.preventDefault();
                if (captchaType === 1) {
                    callBuiltValidation();
                } else if (captchaType === 2) {
                    callGoogleValidation();
                }
            }
        });

        // Show OTP content if pending
        if (securityOtpPending) {
            $('#bodyContent').hide();
            $('#otpContent').show();
            if (otpSentAt) {
                startResendCountdown(otpSentAt);
            }
        } else {
            $('#bodyContent').show();
            $('#otpContent').hide();
        }
        
        // Attach OTP event handlers if OTP form exists
        attachOtpEventHandlers();
    });

    var isEyeOpened = false;

    function loadCaptcha() {
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                document.getElementById("captchaBlock").innerHTML = this.responseText;
                document.getElementById("captchaStr").value = "";
            }
        };
        xhttp.open("GET", "/vtop/get/new/captcha", true);
        xhttp.send();
    }

    function callBuiltValidation() {
        var gvalue = document.getElementById("g-recaptcha-response");
        if (gvalue != null && gvalue != undefined && gvalue != '') {
            document.getElementById('gResponse').value = gvalue.value;
        }
        var form = document.getElementById('vtopLoginForm');
        form.submit();
    }

    function callGoogleValidation() {
        grecaptcha.execute();
    }

    function resetPassword() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var csrfName = "_csrf";
        var csrfValue = "6ac18e9d-668e-4b73-9385-44865df4a427";
        var data = new FormData();
        data.append(csrfName, csrfValue);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                document.getElementById("loginBox").innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/resetPassword", true);
        xhttp.send(data);
    }

    function forgotUserID() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var csrfName = "_csrf";
        var csrfValue = "6ac18e9d-668e-4b73-9385-44865df4a427";
        var data = new FormData();
        data.append(csrfName, csrfValue);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                document.getElementById("loginBox").innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/forgotUserID", true);
        xhttp.send(data);
    }

    function toggleEye() {
        if (isEyeOpened) {
            isEyeOpened = false;
            document.getElementById("passwordIcon").classList.remove('fa-eye-slash');
            document.getElementById("passwordIcon").classList.add('text-danger');
            document.getElementById("passwordIcon").classList.remove('text-primary');
            document.getElementById("passwordIcon").classList.add('fa-eye');
            document.getElementById("password").type = 'password';
        } else {
            isEyeOpened = true;
            document.getElementById("passwordIcon").classList.add('fa-eye-slash');
            document.getElementById("passwordIcon").classList.add('text-primary');
            document.getElementById("passwordIcon").classList.remove('text-danger');
            document.getElementById("passwordIcon").classList.remove('fa-eye');
            document.getElementById("password").type = 'text';
        }
    }

    /* ===== SECURITY OTP FUNCTIONS ===== */
   function submitSecurityOtp() {
    var otpCode = document.getElementById('securityOtpCode').value;
    if (!otpCode || otpCode.length < 6) {
        showOtpError('Please enter a valid 6-digit OTP');
        return;
    }
    
    $.blockUI({
        message: '<h4><img src="assets/gif/ajax-loader_bert.gif" /> Verifying...</h4>'
    });

    var csrfName = "_csrf";
    var csrfValue = "6ac18e9d-668e-4b73-9385-44865df4a427";
    var data = new FormData();
    data.append('otpCode', otpCode);
    if (csrfName) {
        data.append(csrfName, csrfValue);
    }

    var xhttp = new XMLHttpRequest();
    xhttp.onreadystatechange = function() {
        if (this.readyState == 4) {
            $.unblockUI();
            
            if (this.status == 200) {
                try {
                    var response = JSON.parse(this.responseText);
                    
                    if (response.status === 'SUCCESS' && response.redirectUrl) {
                        // Force a complete page reload, not just AJAX navigation
                        window.location.href = response.redirectUrl;
                        return;
                    } else if (response.status === 'INVALID') {
                        showOtpError(response.message || 'Invalid OTP. Please try again.');
                        document.getElementById('securityOtpCode').value = '';
                        document.getElementById('securityOtpCode').focus();
                    } else if (response.status === 'EXPIRED') {
                        showOtpError(response.message || 'OTP has expired. Please resend.');
                        document.getElementById('securityOtpCode').value = '';
                    } else {
                        showOtpError(response.message || 'Verification failed. Please try again.');
                    }
                } catch(e) {
                    console.error('Error:', e);
                    showOtpError('An error occurred. Please try again.');
                }
            } else {
                showOtpError('Server error. Please try again.');
            }
        }
    };
    xhttp.open("POST", "/vtop/validateSecurityOtp", true);
    xhttp.send(data);
}
    function showOtpError(message) {
        var errorDiv = document.getElementById('otpErrorMsg');
        if (errorDiv) {
            errorDiv.innerHTML = '<i class="fa fa-exclamation-triangle"></i> ' + message;
            errorDiv.style.display = 'block';
            setTimeout(function() {
                errorDiv.style.display = 'none';
            }, 5000);
        }
    }

    function resendSecurityOtp() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> Sending OTP...</h4>'
        });
        
        var csrfName = "_csrf";
        var csrfValue = "6ac18e9d-668e-4b73-9385-44865df4a427";
        var data = new FormData();
        if (csrfName) {
            data.append(csrfName, csrfValue);
        }

        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                $.unblockUI();
                try {
                    var response = JSON.parse(this.responseText);
                    if (response.status === 'SUCCESS') {
                        // Reset countdown with new timestamp
                        var newOtpSentAt = new Date().toISOString();
                        startResendCountdown(newOtpSentAt);
                        // Show success message in alert
                        var alertSpan = document.querySelector('#otpAlert .alert span');
                        if (alertSpan) {
                            var originalMsg = alertSpan.innerHTML;
                            alertSpan.innerHTML = '<strong>✓ OTP resent!</strong> ' + (response.message || 'Check your email for new OTP');
                            setTimeout(function() {
                                alertSpan.innerHTML = originalMsg;
                            }, 3000);
                        }
                        // Clear any previous errors
                        var errorDiv = document.getElementById('otpErrorMsg');
                        if (errorDiv) errorDiv.style.display = 'none';
                    } else {
                        showOtpError(response.message || 'Failed to resend OTP');
                    }
                } catch(e) {
                    showOtpError('Failed to resend OTP');
                }
            }
        };
        xhttp.open("POST", "/vtop/resendSecurityOtp", true);
        xhttp.send(data);
    }

    function attachOtpEventHandlers() {
        // Add Enter key handler for OTP input
        var otpInput = document.getElementById('securityOtpCode');
        if (otpInput) {
            otpInput.onkeypress = function(e) {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    submitSecurityOtp();
                }
            };
        }
    }

    var otpCountdownInterval = null;

    function startResendCountdown(sentAtStr) {
        if (otpCountdownInterval) clearInterval(otpCountdownInterval);

        var EXPIRE_SECONDS = 180;
        var sentAt = sentAtStr ? new Date(sentAtStr) : new Date();

        var resendBtn = document.getElementById('resendOtpBtn');
        var secsSpan = document.getElementById('resendSecs');
        var countText = document.getElementById('resendCountdownText');

        if (!resendBtn) return;
        
        resendBtn.disabled = true;
        resendBtn.classList.add('text-muted');
        resendBtn.classList.remove('text-primary');
        if (countText) countText.style.display = 'inline';

        function tick() {
            var elapsed = Math.floor((new Date() - sentAt) / 1000);
            var remaining = EXPIRE_SECONDS - elapsed;

            if (remaining <= 0) {
                clearInterval(otpCountdownInterval);
                resendBtn.disabled = false;
                resendBtn.classList.remove('text-muted');
                resendBtn.classList.add('text-primary');
                if (countText) countText.style.display = 'none';
            } else {
                if (secsSpan) secsSpan.textContent = remaining;
            }
        }

        tick();
        otpCountdownInterval = setInterval(tick, 1000);
    }

    function getOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('forgetPasswordForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                document.getElementById("loginBox").innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/generateOtp", true);
        xhttp.send(data);
    }

    function verifyOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('otpVerificationForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
                var btn = document.getElementById("changePasswordBtn");
                if (btn != null) {
                    btn.addEventListener('click', doChangePassword, false);
                }
            }
        };
        xhttp.open("POST", "/vtop/validateOtp", true);
        xhttp.send(data);
    }

    function regenerateOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('otpVerificationForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/resendOtp", true);
        xhttp.send(data);
    }

    function getUserIDOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('forgetUserIDForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/get/otp/for/forget/userid", true);
        xhttp.send(data);
    }

    function verifyUserIDOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('forgetUserIDForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/validate/user/id/otp", true);
        xhttp.send(data);
    }

    function resendUserIDOTP() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var form = document.getElementById('forgetUserIDForm');
        var data = new FormData(form);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/resend/otp/for/userid", true);
        xhttp.send(data);
    }

    function doChangePassword() {
        $.blockUI({
            message : '<h4><img src="assets/gif/ajax-loader_bert.gif" /> few moments...</h4>'
        });
        var myform = document.getElementById("changePwdForm");
        var data = new FormData(myform);
        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var reqTarget = this.getResponseHeader('wrapper');
                if (reqTarget === 'null' || reqTarget === undefined
                        || reqTarget === null || reqTarget === '') {
                    reqTarget = "loginBox";
                }
                document.getElementById(reqTarget).innerHTML = this.responseText;
                $.unblockUI();
            }
        };
        xhttp.open("POST", "/vtop/allowChangePassword", true);
        xhttp.send(data);
    }

    function myFunction() {
        var newPassword = document.getElementById("newPassword");
        var confirmNewPassword = document.getElementById("confirmNewPassword");
        if (newPassword.type === "password" && confirmNewPassword.type === "password") {
            newPassword.type = "text";
            confirmNewPassword.type = "text";
        } else {
            newPassword.type = "password";
            confirmNewPassword.type = "password";
        }
    }

    /*]]>*/
	