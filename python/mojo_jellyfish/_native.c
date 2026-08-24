#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdint.h>

extern uint32_t mj_soundex_ascii_packed(const char *, int64_t);
extern uint64_t mj_metaphone_ascii_packed(const char *, int64_t);
extern int64_t mj_metaphone_ascii(const char *, int64_t, char *);

static int ascii_input(PyObject *arg, const char **data, Py_ssize_t *length) {
    if (!PyUnicode_Check(arg)) {
        PyErr_Format(
            PyExc_TypeError,
            "s must be str, not %s",
            Py_TYPE(arg)->tp_name
        );
        return -1;
    }
    if (!PyUnicode_IS_ASCII(arg)) {
        return 0;
    }
    *data = PyUnicode_AsUTF8AndSize(arg, length);
    return *data == NULL ? -1 : 1;
}

static PyObject *unicode_fallback(const char *name, PyObject *arg) {
    PyObject *module = PyImport_ImportModule("mojo_jellyfish");
    if (module == NULL) {
        return NULL;
    }
    PyObject *function = PyObject_GetAttrString(module, name);
    Py_DECREF(module);
    if (function == NULL) {
        return NULL;
    }
    PyObject *result = PyObject_CallOneArg(function, arg);
    Py_DECREF(function);
    return result;
}

static PyObject *native_soundex(PyObject *self, PyObject *arg) {
    const char *source;
    Py_ssize_t length;
    int status = ascii_input(arg, &source, &length);
    if (status < 0) {
        return NULL;
    }
    if (status == 0) {
        return unicode_fallback("_soundex_unicode", arg);
    }
    if (length == 0) {
        return PyUnicode_New(0, 127);
    }
    uint32_t packed = mj_soundex_ascii_packed(source, (int64_t)length);
    char result[4] = {
        (char)packed,
        (char)(packed >> 8),
        (char)(packed >> 16),
        (char)(packed >> 24),
    };
    return PyUnicode_DecodeASCII(result, 4, NULL);
}

static PyObject *native_metaphone(PyObject *self, PyObject *arg) {
    const char *source;
    Py_ssize_t length;
    int status = ascii_input(arg, &source, &length);
    if (status < 0) {
        return NULL;
    }
    if (status == 0) {
        return unicode_fallback("_metaphone_unicode", arg);
    }
    if (length == 0) {
        return PyUnicode_New(0, 127);
    }
    if (length <= 32) {
        uint64_t packed = mj_metaphone_ascii_packed(source, (int64_t)length);
        if ((packed >> 63) == 0) {
            char result[8];
            Py_ssize_t written = 0;
            while (written < 8 && (char)(packed >> (8 * written)) != '\0') {
                result[written] = (char)(packed >> (8 * written));
                written++;
            }
            return PyUnicode_DecodeASCII(result, written, NULL);
        }
    }

    Py_ssize_t capacity = 2 * length + 1;
    char local[256];
    char *result = capacity <= (Py_ssize_t)sizeof(local)
        ? local
        : PyMem_Malloc((size_t)capacity);
    if (result == NULL) {
        return PyErr_NoMemory();
    }
    int64_t written = mj_metaphone_ascii(source, (int64_t)length, result);
    PyObject *encoded = PyUnicode_DecodeASCII(result, (Py_ssize_t)written, NULL);
    if (result != local) {
        PyMem_Free(result);
    }
    return encoded;
}

static PyMethodDef methods[] = {
    {"soundex", native_soundex, METH_O, NULL},
    {"metaphone", native_metaphone, METH_O, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "_native",
    NULL,
    -1,
    methods,
};

PyMODINIT_FUNC PyInit__native(void) {
    return PyModule_Create(&module);
}
