import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {logger} from 'firebase-functions';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import fetch from 'node-fetch';
import {GoogleGenerativeAI} from '@google/generative-ai';
import {v4 as uuidv4} from 'uuid';

initializeApp();

const MODEL_NAME = 'gemini-2.5-flash-image'; // 'gemini-3-pro-image-preview' or 'gemini-2.5-flash-image'

export const generateProfilePicture = onCall(
    {
      region: 'us-central1',
      secrets: ['GEMINI_API_KEY'],
      cors: true,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError('unauthenticated', 'Authentication required.');
      }

      const imageUrl = (request.data?.imageUrl as string) ?? '';
      const prompt =
        (request.data?.prompt as string)?.trim() ||
        'Create a professional profile headshot with even lighting.';

      if (!imageUrl.startsWith('http')) {
        throw new HttpsError(
            'invalid-argument',
            'A valid HTTPS imageUrl is required.',
        );
      }

      const geminiApiKey = process.env.GEMINI_API_KEY;
      if (!geminiApiKey) {
        throw new HttpsError(
            'failed-precondition',
            'GEMINI_API_KEY secret is not configured.',
        );
      }

      try {
        const sourceImage = await downloadImage(imageUrl);
        const generatedBuffer = await runGemini(sourceImage, prompt, geminiApiKey);
        const fileInfo = await saveGeneratedImage(uid, generatedBuffer, prompt);

        return {
          imageUrl: fileInfo.imageUrl,
          resultId: fileInfo.resultId,
        };
      } catch (error) {
        logger.error('Generation failed', error);
        if (error instanceof HttpsError) {
          throw error;
        }
        throw new HttpsError('internal', 'Generation failed, please retry later.');
      }
    },
);

const SUPPORTED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

async function downloadImage(imageUrl: string): Promise<{buffer: Buffer; mimeType: string}> {
  const response = await fetch(imageUrl);
  if (!response.ok) {
    throw new HttpsError('invalid-argument', 'Unable to download image.');
  }
  const arrayBuffer = await response.arrayBuffer();
  let mimeType = (response.headers.get('content-type') || 'image/jpeg').toLowerCase();
  if (mimeType === 'image/jpg') {
    mimeType = 'image/jpeg';
  }
  if (!SUPPORTED_MIME_TYPES.has(mimeType)) {
    throw new HttpsError(
        'invalid-argument',
        `Unsupported image mime type: ${mimeType}. Allowed: ${Array.from(SUPPORTED_MIME_TYPES).join(', ')}`,
    );
  }
  return {buffer: Buffer.from(arrayBuffer), mimeType};
}

async function runGemini(
    source: {buffer: Buffer; mimeType: string},
    prompt: string,
    apiKey: string,
): Promise<Buffer> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: MODEL_NAME,
    generationConfig: {
      temperature: 0.65, // 0.35 or 0.65
    },
  });

  const result = await model.generateContent([
    {
      text: 'You are an expert mobile-portrait editor who creates realistic images that look like they were captured on a modern smartphone, keeping people natural and well-integrated into their environments.',
    },
    {text: prompt},
    {
      inlineData: {
        data: source.buffer.toString('base64'),
        mimeType: source.mimeType,
      },
    },
  ]);

  const parts = result.response.candidates?.[0]?.content?.parts ?? [];
  const imagePart = parts.find((part) => part.inlineData?.data);

  if (!imagePart?.inlineData?.data) {
    throw new HttpsError('internal', 'Gemini did not return an image.');
  }

  return Buffer.from(imagePart.inlineData.data, 'base64');
}

async function saveGeneratedImage(
    uid: string,
    buffer: Buffer,
    prompt: string,
): Promise<{imageUrl: string; resultId: string}> {
  const bucket = getStorage().bucket();
  const firestore = getFirestore();
  const resultId = uuidv4();
  const path = `users/${uid}/generated/${resultId}.jpg`;

  const file = bucket.file(path);
  await file.save(buffer, {
    contentType: 'image/jpeg',
    metadata: {
      cacheControl: 'public,max-age=3600',
    },
  });

  const [signedUrl] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + 1000 * 60 * 60 * 24 * 7,
  });

  const userRef = firestore.collection('users').doc(uid);
  await userRef.set(
      {
        lastGeneratedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
  );

  await userRef.collection('results').doc(resultId).set({
    imageUrl: signedUrl,
    imagePath: path,
    prompt,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {imageUrl: signedUrl, resultId};
}

