import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/employee_model.dart';

class EmployeeRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. TAMBAH PEGAWAI BARU
  Future<void> addEmployee(EmployeeModel employee) async {
    await _firestore.collection('employees').add(employee.toMap());
  }

  // 2. AMBIL DAFTAR PEGAWAI (Real-time Stream)
  // Kita filter berdasarkan Cabang user yang login
  Stream<List<EmployeeModel>> getEmployees(String branchId) {
    return _firestore
        .collection('employees')
        .where('branch_id', isEqualTo: branchId)
        .orderBy('name') // Urutkan abjad
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return EmployeeModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // 3. UPDATE DATA PEGAWAI
  Future<void> updateEmployee(String id, Map<String, dynamic> data) async {
    await _firestore.collection('employees').doc(id).update(data);
  }

  // 4. HAPUS PEGAWAI
  Future<void> deleteEmployee(String id) async {
    await _firestore.collection('employees').doc(id).delete();
  }
}