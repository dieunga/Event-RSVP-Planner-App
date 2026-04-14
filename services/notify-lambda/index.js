const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");
const ses = new SESClient({ region: process.env.AWS_REGION || "ap-southeast-1" });

exports.handler = async (event) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json"
  };

  // Handle CORS preflight
  if (event.requestContext?.http?.method === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  let body;
  try {
    body = JSON.parse(event.body);
  } catch {
    return { statusCode: 400, headers, body: JSON.stringify({ error: "Invalid JSON" }) };
  }

  const { userEmail, event: evt } = body;

  if (!userEmail || !evt || !evt.name || !evt.date || !evt.location) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: "Missing required fields" }) };
  }

  const formatDate = (dateStr, timeStr) => {
    const d = new Date(dateStr + "T" + (timeStr || "00:00"));
    const datePart = d.toLocaleDateString("en-US", {
      weekday: "long", month: "long", day: "numeric", year: "numeric"
    });
    const timePart = timeStr
      ? " at " + d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })
      : "";
    return datePart + timePart;
  };

  const capacityRow = evt.capacity
    ? `<tr><td style="padding:8px 0;color:#888;width:120px;">Capacity</td><td style="padding:8px 0;">${evt.capacity} guests</td></tr>`
    : "";
  const descRow = evt.description
    ? `<tr><td style="padding:8px 0;color:#888;vertical-align:top;">Description</td><td style="padding:8px 0;">${evt.description}</td></tr>`
    : "";

  const params = {
    Source: process.env.SES_SENDER,
    Destination: { ToAddresses: [userEmail] },
    Message: {
      Subject: { Data: `Event Created: ${evt.name}` },
      Body: {
        Html: {
          Data: `
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#f9f7f4;font-family:Georgia,serif;">
  <div style="max-width:580px;margin:40px auto;background:#fff;border:1px solid #e8e0d4;padding:40px;">
    <div style="border-bottom:1px solid #d4af7a;padding-bottom:20px;margin-bottom:28px;">
      <span style="font-size:13px;letter-spacing:3px;color:#b08d60;text-transform:uppercase;">Soirée</span>
      <h1 style="margin:8px 0 0;font-size:26px;font-weight:400;color:#1a1a1a;">Your event has been created</h1>
    </div>
    <table style="width:100%;border-collapse:collapse;">
      <tr><td style="padding:8px 0;color:#888;width:120px;">Event</td><td style="padding:8px 0;font-weight:500;color:#1a1a1a;">${evt.name}</td></tr>
      <tr><td style="padding:8px 0;color:#888;">Date</td><td style="padding:8px 0;">${formatDate(evt.date, evt.time)}</td></tr>
      <tr><td style="padding:8px 0;color:#888;">Location</td><td style="padding:8px 0;">${evt.location}</td></tr>
      <tr><td style="padding:8px 0;color:#888;">Category</td><td style="padding:8px 0;">${evt.category || "Event"}</td></tr>
      ${capacityRow}
      ${descRow}
    </table>
    <p style="margin-top:32px;color:#aaa;font-size:12px;border-top:1px solid #f0ebe3;padding-top:20px;">
      This is an automated notification from Soirée Event Planner.
    </p>
  </div>
</body>
</html>`
        }
      }
    }
  };

  try {
    await ses.send(new SendEmailCommand(params));
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ message: "Notification sent" })
    };
  } catch (err) {
    console.error("SES error:", err);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ error: "Failed to send email" })
    };
  }
};
