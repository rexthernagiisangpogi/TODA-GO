/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
admin.initializeApp();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({maxInstances: 10});

// Deliver queued notifications from Firestore via FCM
exports.deliverQueuedNotification = onDocumentCreated(
    "notifications/{docId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const data = snap.data();
      if (!data) return;

      // Only process queued notifications
      if (data.status && data.status !== "queued") {
        return;
      }

      try {
        const title = typeof data.title === "string" ? data.title : undefined;
        const body = typeof data.body === "string" ? data.body : undefined;
        const payloadData = data.data || {};

        let message = null;

        const isTopic = data.target === "topic" &&
            typeof data.topic === "string" &&
            data.topic.length > 0;

        if (isTopic) {
          message = {
            topic: data.topic,
            notification: title || body ? {title, body} : undefined,
            data: Object.fromEntries(
                Object.entries(payloadData)
                    .map(([k, v]) => [k, String(v)]),
            ),
          };
        }

        if (!message) {
          logger.warn(
              "Notification skipped: unsupported target or missing topic",
              data,
          );
          await snap.ref.update({
            status: "skipped",
            reason: "unsupported_target",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return;
        }

        const id = await admin.messaging().send(message);
        logger.info("FCM sent", {id, topic: message.topic});

        await snap.ref.update({
          status: "sent",
          fcmMessageId: id,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err) {
        logger.error("Failed to send notification", err);
        await snap.ref.update({
          status: "failed",
          error: String(err && err.message ? err.message : err),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    },
);
