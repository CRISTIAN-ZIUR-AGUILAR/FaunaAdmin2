import 'package:emailjs/emailjs.dart';
import 'package:emailjs/emailjs.dart' as EmailJS;

class EmailService {
  static Future<void> enviarCorreoConfirmacion(String nombre, String correo) async {
    try {
      final response = await EmailJS.send(
        'service_qgmr75k',
        'template_ptw89eo',
        {
          'to_name': nombre,
          'email': correo,
        },
        Options(
          publicKey: 'JP1_dkktWzumXlmbd',
        ),
      );

      print('✅ Correo enviado correctamente');
    } catch (error) {
      print('❌ Error al enviar correo: $error');
    }
  }
}
