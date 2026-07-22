import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {getStorage} from "firebase-admin/storage";

initializeApp();

export const db = getFirestore();
export const auth = getAuth();
export const messaging = getMessaging();
export const storage = getStorage();
