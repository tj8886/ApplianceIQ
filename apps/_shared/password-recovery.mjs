export function passwordRecovery(auth, notify) {
  let recoveryUser = null, busy = false;
  const subscription = auth.onAuthStateChange((event, session) => {
    if (event === 'PASSWORD_RECOVERY' && session?.user?.id) {
      recoveryUser = session.user.id;
      notify('ready', 'Choose a new password for your account.');
    } else if (event === 'SIGNED_OUT' || (recoveryUser && session?.user?.id !== recoveryUser)) {
      recoveryUser = null;
      notify('expired', 'This reset session has expired. Request a new reset email.');
    }
  });
  return {
    async initialize() {
      try {
        const result = await auth.getSession();
        if (result.error || !recoveryUser) notify('request', 'Enter your account email to request a password reset.');
      } catch { notify('request', 'The reset link could not be verified. Request a new reset email.'); }
    },
    async request(email, redirectTo) {
      if (busy) return false;
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { notify('error', 'Enter a valid account email.'); return false; }
      busy = true;
      try {
        const result = await auth.resetPasswordForEmail(email, { redirectTo });
        if (result.error) throw result.error;
        notify('sent', 'Reset request accepted. If this email has an account, check your inbox and spam folder for the reset link.');
        return true;
      } catch { notify('error', 'The reset email could not be requested. Please try again later.'); return false; }
      finally { busy = false; }
    },
    async save(password, confirmation) {
      if (busy) return false;
      if (!recoveryUser) { notify('expired', 'Open a valid password reset link from your email first.'); return false; }
      if (password.length < 12) { notify('error', 'Use at least 12 characters for your new password.'); return false; }
      if (password !== confirmation) { notify('error', 'The two passwords do not match.'); return false; }
      busy = true;
      try {
        const result = await auth.getUser();
        if (result.error || result.data?.user?.id !== recoveryUser) {
          recoveryUser = null;
          notify('expired', 'This reset session has expired. Request a new reset email.');
          return false;
        }
        const updated = await auth.updateUser({ password });
        if (updated.error) throw updated.error;
        recoveryUser = null;
        // Password success does not depend on a later local sign-out request succeeding.
        try { await auth.signOut({ scope: 'local' }); } catch {}
        notify('saved', 'Your password has been changed. Return to sign in with your new password.');
        return true;
      } catch { notify('error', 'Your password was not changed. Try a stronger password, or request a new reset link.'); return false; }
      finally { busy = false; }
    },
    dispose() { subscription.data.subscription.unsubscribe(); }
  };
}
