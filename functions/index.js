/**
 * PrePora Cloud Functions
 * - deleteUser: permanently delete a user from Firebase Auth (used by admin)
 * - updatePassword: change a user's password (admin action, used for students/assistants)
 * - dailyStreakNotification: scheduled daily 9 AM push to all students via FCM
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Delete a user from Firebase Auth (and their users/{uid} doc handled by caller).
 */
exports.deleteUser = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.data && request.data.uid;
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'uid is required');
  }
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  try {
    await admin.auth().deleteUser(uid);
    return { success: true };
  } catch (e) {
    throw new HttpsError('internal', `Failed to delete user: ${e.message}`);
  }
});

/**
 * Change a user's password (admin only). Requires the caller to be an admin.
 */
exports.updatePassword = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.data && request.data.uid;
  const newPassword = request.data && request.data.newPassword;
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'uid is required');
  }
  if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 6) {
    throw new HttpsError('invalid-argument', 'Password must be at least 6 characters');
  }
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  // Only admin can change others' passwords
  const callerUid = request.auth.uid;
  try {
    const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
    const callerRole = (callerDoc.data() && callerDoc.data().role) || '';
    if (callerRole !== 'admin') {
      throw new HttpsError('permission-denied', 'Only admins can change passwords');
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError('internal', `Failed to verify admin: ${e.message}`);
  }
  try {
    await admin.auth().updateUser(uid, { password: newPassword });
    return { success: true };
  } catch (e) {
    throw new HttpsError('internal', `Failed to update password: ${e.message}`);
  }
});

/**
 * Called by a student whose free trial has expired. Flipping the global
 * "paidAccess" setting ON mirrors the admin's manual toggle, so all unverified
 * students then see the paywall until manually verified.
 */
exports.expireFreeTrial = onCall({ maxInstances: 10 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = request.auth.uid;
  const now = Date.now();
  try {
    const userRef = admin.firestore().collection('users').doc(uid);
    const userDoc = await userRef.get();
    const data = userDoc.data() || {};
    const endsAt = data.freeTrialEndsAt;
    const endMs = endsAt && endsAt.toMillis ? endsAt.toMillis() : null;
    if (data.freeTrialActive === true && endMs !== null && endMs <= now) {
      await admin
        .firestore()
        .collection('settings')
        .doc('general')
        .set({ paidAccess: true }, { merge: true });
      await userRef.update({ freeTrialActive: false });
      return { flipped: true };
    }
    return { flipped: false };
  } catch (e) {
    throw new HttpsError('internal', `Failed to expire trial: ${e.message}`);
  }
});

/**
 * Daily streak reminder — every day at 9 AM local (Asia/Karachi assumed PKT)
 * Sends an FCM notification to every verified, non-blocked student with an FCM token.
 */
exports.dailyStreakNotification = onSchedule(
  {
    schedule: '0 9 * * *',
    timeZone: 'Asia/Karachi',
    maxInstances: 1,
  },
  async () => {
    const usersSnap = await admin
      .firestore()
      .collection('users')
      .where('role', '==', 'student')
      .get();

    const tokens = [];
    const now = Date.now();

    usersSnap.forEach((doc) => {
      const data = doc.data();
      const token = data.fcmToken;
      if (!token || typeof token !== 'string') return;
      if (data.blocked === true) return;
      // Only notify users who have NOT logged in today (streak nudge)
      const lastLogin = data.lastLogin && data.lastLogin.toMillis ? data.lastLogin.toMillis() : null;
      if (lastLogin) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (lastLogin >= today.getTime()) return; // already active today
      }
      // Check trial: if free trial is still active, don't send paid nudge
      const trialEnd = data.freeTrialEndsAt && data.freeTrialEndsAt.toMillis ? data.freeTrialEndsAt.toMillis() : null;
      if (trialEnd && trialEnd > now) return; // still in trial, skip nudge
      tokens.push(token);
    });

    if (tokens.length === 0) return;

    const payload = {
      notification: {
        title: 'Time to study!',
        body: 'Your learning journey is waiting. Open PrePora and continue where you left off.',
      },
      data: {
        type: 'streak_reminder',
      },
    };

    // FCM send each message (SDK v2 style) in chunks
    const CHUNK = 500;
    for (let i = 0; i < tokens.length; i += CHUNK) {
      const chunk = tokens.slice(i, i + CHUNK);
      const messages = chunk.map((token) => ({ ...payload, token }));
      await admin.messaging().sendEach(messages);
    }
  }
);